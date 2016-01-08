# cleansweep

![](screenshot.png)

Get notified of outdated packages on your machine.

### Usage

```sh
$ ./cleansweep.sh
```

### Examples


```sh
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

The machine uuid is stored in `.patchwork/uuid` by default. You can reset the uuid by deleting this file. This may be required when upgradng the operating system.

## License

MIT © Patchwork Security, Inc.
