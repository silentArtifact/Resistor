import argparse
import json
import httpx


def export_data(url, outfile, passphrase=None):
    params = {}
    if passphrase:
        params['passphrase'] = passphrase
    r = httpx.get(f"{url}/export", params=params)
    r.raise_for_status()
    with open(outfile, 'w') as f:
        json.dump(r.json(), f)


def import_data(url, infile, passphrase=None):
    with open(infile) as f:
        data = json.load(f)
    params = {}
    if passphrase:
        params['passphrase'] = passphrase
    r = httpx.post(f"{url}/import", params=params, json=data)
    r.raise_for_status()
    print("Import successful")


def main():
    parser = argparse.ArgumentParser(description="Resistor data helper")
    parser.add_argument('--url', default='http://localhost:8080')
    sub = parser.add_subparsers(dest='cmd', required=True)

    exp = sub.add_parser('export', help='Export data to file')
    exp.add_argument('outfile')
    exp.add_argument('--passphrase')

    imp = sub.add_parser('import', help='Import data from file')
    imp.add_argument('infile')
    imp.add_argument('--passphrase')

    args = parser.parse_args()
    if args.cmd == 'export':
        export_data(args.url, args.outfile, args.passphrase)
    else:
        import_data(args.url, args.infile, args.passphrase)


if __name__ == '__main__':
    main()
