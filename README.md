# cleansweep

**Need a cleansweep API token?** Sign up for one on our [website](https://patchworksecurity.com)

![](screenshot.png)

Get notifications when packages are outdated. Register your installed packages with us and we will contact you as new security updates are released. No need to follow mailing lists or filtering RSS feeds for relevant packages.

### Usage

You will need a cleansweep API token to use this service. The token should either be exported as an environment variable or set for the script.

```sh
$ ./cleansweep.sh
```

### Examples


```sh
# Register a machine
API_TOKEN=6afe45ef0b9cd5d99b0a34aff1982aaf ./cleansweep.sh

# Register with machine name `testing`:
FRIENDLY_NAME=testing ./cleansweep.sh

# Store / load configuration from `.config` directory:
CONFIG_DIR=.config ./cleansweep.sh

# Enable verbose output
# This outputs all your installed packages to the console
./cleansweep.sh -v
```

### Options

#### `-v`

Enable verbose output to stderr

### Environment variables

- `API_TOKEN`: The API token to use
- `FRIENDLY_NAME`: Specify a custom name for this machine, `hostname` by default
- `CONFIG_DIR`: Specify an alternative location to store metadata, `.patchwork` by default


### Configuration

The machine uuid is stored in `.patchwork/uuid` by default. You can reset the uuid by deleting that file. This may be required when upgradng the operating system.

## License

MIT © Patchwork Security, Inc.
