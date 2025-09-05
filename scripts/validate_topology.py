#!/usr/bin/env python3
import sys, json

try:
    import yaml  # PyYAML
except Exception as e:
    sys.stderr.write("PyYAML not available. Please install pyyaml or run the external validator.\n")
    sys.exit(2)

def err(msg):
    print(f"ERROR: {msg}")
    return False

def ok(msg):
    print(f"OK: {msg}")

def validate(doc):
    ok_count = 0
    root = doc.get('ietf-network:networks')
    if root is None:
        return err("missing 'ietf-network:networks'")
    nets = root.get('network')
    if not isinstance(nets, list) or not nets:
        return err("'network' must be a non-empty list")
    ok("found networks: %d" % len(nets))
    for n in nets:
        nid = n.get('network-id')
        if not nid:
            return err("network without 'network-id'")
        ok(f"network-id: {nid}")
        # nodes
        nodes = n.get('node', [])
        if nodes:
            for node in nodes:
                nid2 = node.get('node-id')
                if not nid2:
                    return err(f"node in {nid} missing 'node-id'")
                tps = node.get('ietf-network-topology:termination-point', [])
                for tp in tps:
                    if not tp.get('tp-id'):
                        return err(f"tp in node {nid2} missing 'tp-id'")
        # links
        links = n.get('ietf-network-topology:link', [])
        for lk in links:
            if not lk.get('link-id'):
                return err(f"link in {nid} missing 'link-id'")
            src = lk.get('ietf-network-topology:source') or {}
            dst = lk.get('ietf-network-topology:destination') or {}
            if not (src.get('source-node') and src.get('source-tp')):
                return err(f"link {lk.get('link-id')} missing source-node/source-tp")
            if not (dst.get('dest-node') and dst.get('dest-tp')):
                return err(f"link {lk.get('link-id')} missing dest-node/dest-tp")
    return True

def main():
    if len(sys.argv) < 2:
        print("usage: validate_topology.py <yaml>")
        sys.exit(2)
    path = sys.argv[1]
    with open(path, 'r') as f:
        doc = yaml.safe_load(f)
    ok(f"loaded: {path}")
    if validate(doc):
        print("RESULT: PASS (structural checks)")
        sys.exit(0)
    else:
        print("RESULT: FAIL")
        sys.exit(1)

if __name__ == '__main__':
    main()

