# ipam-example

A model repository for [easytofu/terraform-provider-github-ipam](https://github.com/easytofu/terraform-provider-github-ipam):
IP address management where a GitHub repo is the source of truth and Terraform/OpenTofu hands out CIDRs.

Copy this repo's layout to run IPAM for your own organisation.

> After the first `apply`, the provider writes a generated dashboard to `.github/README.md`. GitHub shows that
> file on the repo's front page in place of this one. This guide stays at [`README.md`](README.md).

## Layout

```
config/
  pools.yaml          address plan: pools and their CIDRs (people edit this, by PR)
  allocations.yaml    every CIDR handed out (the provider edits this, never people)
.github/
  CODEOWNERS          pools.yaml needs a network owner's review
  workflows/validate.yml
  README.md           generated dashboard (appears after the first apply)
  ipam/pools/*.md     generated page per pool (appears after the first apply)
scripts/
  validate_ipam.py    CI checks for both config files
examples/consumer/    a stack that takes a VPC block and subnets from a pool
```

## How it works

```
 people ── PR ──▶ config/pools.yaml            (reviewed, validated in CI)
                        │ read
 tofu apply ──▶ github-ipam provider ──▶ config/allocations.yaml   (commit to main, SHA-checked)
                                     └─▶ .github/README.md + .github/ipam/pools/*.md  (dashboard)
```

- **Pools** are the address plan, e.g. `development = 10.48.0.0/12`. They change rarely and always by pull request.
- **Allocations** are created by `github-ipam_allocation` resources in any Terraform stack. The provider:
  1. reads `allocations.yaml` and its blob SHA,
  2. finds the next free, aligned block,
  3. writes the file back with that SHA.
- If another apply wrote first, GitHub rejects the stale SHA (409). The provider then re-reads and retries with
  backoff. So parallel applies across teams never hand out the same block.
- Two allocation modes:
  - `pool_id`: a top-level block from a pool, such as a VPC.
  - `parent_cidr`: a block inside an existing allocation, such as a subnet.
- `status = "reservation"` holds space without letting anything be carved out of it. `contiguous_with` places a
  block right next to another one.

## The address plan in this repo

| Pool | CIDR | Notes |
| --- | --- | --- |
| `prod-eu-west-1` | 10.0.0.0/12 | 16 × /16 VPCs |
| `prod-ap-southeast-2` | 10.16.0.0/12 | |
| `staging` | 10.32.0.0/12 | |
| `development` | 10.48.0.0/12 | used by `examples/consumer` |
| `shared-services` | 10.64.0.0/16 | transit, VPN, DNS |
| `container-overlay` | 172.16.0.0/13, 172.24.0.0/14 | two CIDRs: filled in order |
| `reserved-future` | 10.128.0.0/9 | `reserved: true`, so no allocations |
| `reserved-lan` | 192.168.0.0/16 | `reserved: true`, to avoid clashing with home/office LANs |

10.65.0.0 – 10.127.255.255 is left unassigned as headroom for new pools.

## Set up your own

1. **Create a private repo** with this layout. Keep `config/allocations.yaml` as an empty database:
   ```yaml
   version: "1.0"
   allocations: {}
   ```
2. **Write your address plan** in `config/pools.yaml`. Then run the checks:
   ```bash
   pip install pyyaml && python scripts/validate_ipam.py
   ```
   Rules for a good plan:
   - Pool IDs are permanent, because stacks reference them.
   - Leave headroom between pools.
   - Reserve ranges you must never use.
3. **Create a token for the provider.** It needs **Contents: read and write** on this repo only.
   - For people running applies by hand: a fine-grained personal access token scoped to this one repository.
   - For CI: a GitHub App installed on this repo only, with Contents read/write. Mint a token per job (see below).
     The default `GITHUB_TOKEN` of a *different* repo's workflow cannot write here.
4. **Protect `main`, but let the provider through.** The provider commits straight to `main` through the Contents
   API; it never opens PRs. Set up a branch ruleset on `main`:
   - require a pull request and code-owner review,
   - add the IPAM GitHub App (or the PAT's user) to the bypass list.

   Without the bypass, every apply fails. Rulesets on private repos need GitHub Pro, Team or Enterprise.
5. **Use it from your stacks.** See [`examples/consumer`](examples/consumer). Pass the token as a variable:
   ```bash
   export TF_VAR_github_token=github_pat_...
   cd examples/consumer && tofu init && tofu apply
   ```

### From GitHub Actions in another repo

```yaml
- uses: actions/create-github-app-token@v1
  id: ipam
  with:
    app-id: ${{ vars.IPAM_APP_ID }}
    private-key: ${{ secrets.IPAM_APP_PRIVATE_KEY }}
    owner: dddaaammmooo
    repositories: ipam-example

- run: tofu apply -auto-approve
  env:
    TF_VAR_github_token: ${{ steps.ipam.outputs.token }}
```

## Day-to-day

| Task | How |
| --- | --- |
| Get a VPC block | `github-ipam_allocation` with `pool_id` and `cidr_mask` |
| Get subnets | `github-ipam_allocation` with `parent_cidr = <vpc allocation>.cidr` |
| Preview the next free block | `data "github-ipam_next_available"` with `pool_id` or `parent_cidr` |
| Look up a block someone else owns | `data "github-ipam_allocation"` by `name` or `id` |
| Add a pool | PR to `config/pools.yaml` |
| Grow a pool | PR appending another CIDR to its `cidr` list |
| Retire a block | Remove the resource and apply. Children must go first; the provider refuses to delete a parent with children |
| Adopt an existing block | `tofu import github-ipam_allocation.x <uuid>` (the id from `allocations.yaml`) |

## Things to know (provider v0.0.21)

- **No token from the environment.** The docs say the token can come from `GITHUB_TOKEN`, but the code never reads
  it, and `token` is required. Set `TF_VAR_github_token` instead.
- **The provider name is `github-ipam`.** Resources are `github-ipam_allocation`, `github-ipam_pool`, and so on.
  Parts of the upstream README use `gitipam` and `registry.opentofu.org/easytofu/gitipam`, which don't exist. Use
  `source = "easytofu/github-ipam"`.
- **`allocations.yaml` is YAML.** The upstream docs show JSON.
- **Pick one way to manage pools.** The `github-ipam_pool` resource writes `pools.yaml` directly, which skips PR
  review. This repo manages pools by PR only. If you use the resource, drop the CODEOWNERS rule and accept that.
- **Expect noisy history.** Each apply commits `allocations.yaml`, then refreshes the dashboard files in separate
  commits.
- **IPv4 only.** The allocator does its arithmetic on 32-bit addresses.
- **Never hand-edit `allocations.yaml`.** Terraform state holds each allocation's UUID; editing the file breaks
  that link. CI fails any PR that touches it unless it carries the `ipam-manual-fix` label.

## CI

`.github/workflows/validate.yml` runs on every PR and every push to `main`. Pushes include the provider's own
commits, so its writes are checked too. It runs three checks:

- `scripts/validate_ipam.py` checks pools and allocations:
  - pool CIDRs are valid, aligned, RFC 1918 and non-overlapping, with kebab-case IDs,
  - every allocation sits inside its pool or parent,
  - siblings don't overlap,
  - nothing is allocated from a reserved pool or parent,
  - IDs are unique.
- A PR that hand-edits `allocations.yaml` fails.
- `tofu fmt`, `init` and `validate` run on the consumer example.
