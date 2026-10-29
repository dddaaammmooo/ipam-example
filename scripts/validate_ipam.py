#!/usr/bin/env python3
"""Check config/pools.yaml and config/allocations.yaml for mistakes.

The provider trusts these files. This script catches what a reviewer can
miss in a pull request:

pools.yaml
  - every pool has at least one CIDR, each CIDR parses and is on its
    network boundary (10.1.0.0/16, not 10.1.2.3/16)
  - every CIDR is private address space (RFC 1918)
  - no two pool CIDRs overlap
  - pool IDs are lowercase kebab-case (they are used as Terraform inputs
    and as file names under .github/ipam/pools/)

allocations.yaml
  - every allocation belongs to a pool that exists
  - top-level allocations sit inside their pool's CIDRs, and sub-allocations
    sit inside a parent allocation that exists
  - siblings (same pool and same parent) never overlap
  - ids are unique; nothing is allocated from a reserved pool or parent

Usage: scripts/validate_ipam.py [--pools PATH] [--allocations PATH]
Exit code 0 when clean, 1 when any problem is found.
"""

import argparse
import ipaddress
import os
import re
import sys

import yaml

RFC1918 = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
]
POOL_ID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


def load(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def parse_cidr(value, where, errors):
    try:
        return ipaddress.ip_network(value, strict=True)
    except ValueError as e:
        errors.append(f"{where}: {value!r} is not a valid network CIDR ({e})")
        return None


def check_pools(doc, errors):
    pools = doc.get("pools")
    if not isinstance(pools, dict):
        errors.append("pools.yaml: top-level 'pools' map is missing")
        return {}

    nets = {}  # pool_id -> [network]
    seen = []  # (network, pool_id)
    for pool_id, pool in pools.items():
        where = f"pools.yaml: pool {pool_id!r}"
        if not POOL_ID.match(str(pool_id)):
            errors.append(f"{where}: id must be lowercase kebab-case")
        cidrs = (pool or {}).get("cidr") or []
        if not cidrs:
            errors.append(f"{where}: has no CIDRs")
        nets[pool_id] = []
        for value in cidrs:
            net = parse_cidr(value, where, errors)
            if net is None:
                continue
            if not any(net.subnet_of(r) for r in RFC1918 if r.version == net.version):
                errors.append(f"{where}: {net} is not RFC 1918 private space")
            for other, other_id in seen:
                if net.overlaps(other):
                    errors.append(f"{where}: {net} overlaps {other} in pool {other_id!r}")
            seen.append((net, pool_id))
            nets[pool_id].append(net)
    return nets


def check_allocations(doc, pools_doc, pool_nets, errors):
    allocations = doc.get("allocations") or {}
    if not isinstance(allocations, dict):
        errors.append("allocations.yaml: 'allocations' must be a map of pool_id -> list")
        return 0

    pools = pools_doc.get("pools") or {}
    ids = set()
    count = 0
    for pool_id, items in allocations.items():
        if pool_id not in pools:
            errors.append(f"allocations.yaml: pool {pool_id!r} is not defined in pools.yaml")
            continue
        by_cidr = {}
        for item in items or []:
            count += 1
            where = f"allocations.yaml: {pool_id}/{item.get('name') or item.get('id')}"
            net = parse_cidr(item.get("cidr"), where, errors)
            if net is None:
                continue
            if item.get("id") in ids:
                errors.append(f"{where}: duplicate id {item.get('id')}")
            ids.add(item.get("id"))
            by_cidr[str(net)] = (net, item)

        siblings = {}  # parent cidr (or None) -> [(net, name)]
        for net, item in by_cidr.values():
            where = f"allocations.yaml: {pool_id}/{item.get('name') or item.get('id')}"
            parent = item.get("parent_cidr")
            if parent:
                if parent not in by_cidr:
                    errors.append(f"{where}: parent {parent} is not an allocation in this pool")
                else:
                    parent_net, parent_item = by_cidr[parent]
                    if not net.subnet_of(parent_net):
                        errors.append(f"{where}: {net} is outside its parent {parent_net}")
                    if parent_item.get("reserved"):
                        errors.append(f"{where}: parent {parent_net} is a reservation")
            else:
                if pools[pool_id].get("reserved"):
                    errors.append(f"{where}: pool {pool_id!r} is reserved")
                if not any(net.subnet_of(p) for p in pool_nets.get(pool_id, [])):
                    errors.append(f"{where}: {net} is outside pool {pool_id!r}")
            for other, other_name in siblings.setdefault(parent, []):
                if net.overlaps(other):
                    errors.append(f"{where}: {net} overlaps sibling {other} ({other_name})")
            siblings[parent].append((net, item.get("name")))
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--pools", default="config/pools.yaml")
    parser.add_argument("--allocations", default="config/allocations.yaml")
    args = parser.parse_args()

    errors = []
    pools_doc = load(args.pools)
    pool_nets = check_pools(pools_doc, errors)
    count = check_allocations(load(args.allocations), pools_doc, pool_nets, errors)

    for e in errors:
        print(f"::error::{e}" if "GITHUB_ACTIONS" in os.environ else f"ERROR {e}")
    if errors:
        print(f"{len(errors)} problem(s) found")
        return 1
    print(f"OK: {len(pool_nets)} pools, {count} allocations")
    return 0


if __name__ == "__main__":
    sys.exit(main())
