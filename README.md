# FRITZ!Box Fauxmo

Control **FRITZ!DECT smart plugs** with **Amazon Alexa** using [Fauxmo](https://github.com/n8henrie/fauxmo) and the FRITZ!Box AHA HTTP interface.

The project provides a lightweight local integration between Alexa and FRITZ!DECT devices without requiring:

* Home Assistant
* openHAB
* Matter
* FRITZ! Smart Gateway
* an external cloud service
* an Alexa Smart Home Skill

The current implementation focuses on **ON/OFF control and state reporting**.

---

## How it works

```text
Amazon Echo
    │
    │ Local network / SSDP
    ▼
Fauxmo
    │
    │ Python plugin
    ▼
fritz_plugin.py
    │
    │ FRITZ!Box AHA HTTP API
    ▼
FRITZ!Box
    │
    ▼
FRITZ!DECT smart plug
```

Fauxmo emulates a compatible local smart-home device that Alexa can discover.

When Alexa receives a command such as:

> "Alexa, turn on the desk lamp"

Fauxmo calls `fritz_plugin.py`, which authenticates with the FRITZ!Box and sends the appropriate AHA command to the FRITZ!DECT device.

---

## Features

* Local Alexa discovery using Fauxmo
* ON/OFF control
* Device state reporting
* Automatic discovery of FRITZ!DECT devices
* Automatic generation of the Fauxmo configuration
* Support for FRITZ!Box AHA authentication
* Automatic FRITZ!Box session renewal
* Docker support
* Credentials supplied through environment variables
* No credentials stored in the generated `config.json`

---

## Current limitations

The current version does **not** provide:

* temperature sensors in Alexa
* energy consumption reporting
* power measurements in Alexa
* Matter support
* an Alexa Smart Home Skill
* remote/cloud control

Temperature and energy data may be available through the FRITZ!Box AHA interface, but exposing these capabilities to Alexa requires a different integration approach.

---

# Requirements

## Hardware

The project was developed and tested with:

* FRITZ!Box 7590
* FRITZ!DECT 200 smart plugs
* Amazon Echo Dot 3rd generation

Other FRITZ!Box models and FRITZ!DECT devices may also work if they expose the required AHA HTTP API.

An Amazon Echo device must be connected to the same local network as the machine running Fauxmo.

---

## Software

You need:

* Linux host or NAS
* Docker
* Bash
* `curl`
* `iconv`
* `md5sum`
* Python 3
* network access between the Docker host, FRITZ!Box and Echo

The `detect_dect.sh` script is executed on the host/NAS.

Fauxmo itself runs inside Docker.

---

# Project structure

```text
fritzbox-fauxmo/
├── .gitignore
├── Dockerfile
├── README.md
├── detect_dect.sh
├── fritz_plugin.py
└── run.sh
```

The following files are generated or contain local secrets and should **not** be committed:

```text
.env
config.json
```

---

# Installation

## 1. Clone the repository

```bash
git clone https://github.com/lucamemini/fritzbox-fauxmo.git
cd fritzbox-fauxmo
```

Replace the URL if your repository is hosted under a different GitHub account or name.

---

## 2. Configure FRITZ!Box credentials

Create a local `.env` file:

```bash
nano .env
```

Add:

```dotenv
FRITZ_USER=your_fritzbox_username
FRITZ_PASS=your_fritzbox_password
FRITZ_HOST=http://fritz.box
```

Do not commit this file.

The `.gitignore` included with the project excludes `.env`.

Protect the file:

```bash
chmod 600 .env
```

---

## 3. Load the environment variables

Before running the discovery script:

```bash
set -a
source .env
set +a
```

You can verify that the username is loaded:

```bash
echo "$FRITZ_USER"
```

Do not print the password.

---

# Discover FRITZ!DECT devices

Run:

```bash
./detect_dect.sh
```

The script:

1. connects to the FRITZ!Box
2. obtains an AHA login challenge
3. calculates the authentication response
4. authenticates with the FRITZ!Box
5. retrieves the complete Smart Home device list
6. identifies devices and groups
7. assigns Fauxmo ports
8. generates `config.json`

Example output:

```text
FRITZ!Box login successful

=== Devices found ===
AIN                  Name                 Model
------------------------------------------------------------
08761 1234567-1      Desk Lamp            FRITZ!DECT 200
08761 1234567-2      TV                   FRITZ!DECT 200

Wrote config.json with 2 devices.

Credentials are NOT stored in config.json.
```

---

# About `config.json`

`config.json` is generated automatically by `detect_dect.sh`.

It contains the Fauxmo configuration and the discovered devices.

For example:

```json
{
  "FAUXMO": {
    "ip_address": "auto"
  },
  "PLUGINS": {
    "FritzDectPlugin": {
      "path": "/app/fritz_plugin.py",
      "DEVICES": [
        {
          "name": "Desk Lamp",
          "port": 12340,
          "fritz_host": "http://fritz.box",
          "ain": "08761 1234567-1"
        }
      ]
    }
  }
}
```

Notice that the FRITZ!Box username and password are **not** stored in this file.

The plugin obtains them from:

```text
FRITZ_USER
FRITZ_PASS
```

at runtime.

`config.json` is therefore generated locally and is excluded from Git.

---

# Start Fauxmo

After generating `config.json`, run:

```bash
./run.sh
```

The script:

1. verifies that `FRITZ_USER` and `FRITZ_PASS` are available
2. builds the Docker image
3. removes an existing container with the same name
4. starts the new container
5. passes the FRITZ!Box credentials to the container
6. enables host networking
7. configures the container to restart automatically

The container is called:

```text
fritz-fauxmo
```

---

# Check the container

Check whether it is running:

```bash
docker ps
```

View the logs:

```bash
docker logs fritz-fauxmo
```

Follow the logs in real time:

```bash
docker logs -f fritz-fauxmo
```

You should see messages similar to:

```text
[Desk Lamp] Login successful
```

when Fauxmo communicates with the FRITZ!Box.

---

# Alexa setup

Once Fauxmo is running, ask Alexa to discover devices:

> "Alexa, discover my devices."

Alternatively, use the Alexa app and start device discovery.

The FRITZ!DECT devices discovered by `detect_dect.sh` should appear as smart-home devices.

You can then use commands such as:

> "Alexa, turn on Desk Lamp."

or:

> "Alexa, turn off Desk Lamp."

The exact device names depend on the names configured in the FRITZ!Box.

---

# Why host networking is used

The Docker container is started with:

```bash
--network host
```

This is important because Fauxmo relies on local network discovery mechanisms used by Alexa.

Using Docker's default bridge network can prevent Alexa from discovering the emulated devices correctly.

For this reason, the project intentionally uses host networking rather than normal Docker port mapping.

---

# Updating the device configuration

If you add, remove or rename a FRITZ!DECT device in the FRITZ!Box, regenerate the Fauxmo configuration:

```bash
set -a
source .env
set +a

./detect_dect.sh
```

Then restart the container:

```bash
./run.sh
```

The new configuration will be included in the newly built container.

---

# Security

## Never commit credentials

Do not put your FRITZ!Box credentials directly into:

* `detect_dect.sh`
* `fritz_plugin.py`
* `run.sh`
* `Dockerfile`
* `config.json`
* `README.md`

Credentials should only be supplied through environment variables.

The recommended local configuration is:

```text
.env
```

with:

```dotenv
FRITZ_USER=...
FRITZ_PASS=...
FRITZ_HOST=http://fritz.box
```

The `.env` file must remain local.

---

## Verify Git is ignoring sensitive files

Run:

```bash
git status
```

`config.json` and `.env` should not appear as untracked files.

You can also check:

```bash
git check-ignore -v config.json
git check-ignore -v .env
```

Both commands should show the corresponding `.gitignore` rule.

---

## If `config.json` was already tracked

If you previously added `config.json` to Git, `.gitignore` alone does not remove it from tracking.

Run:

```bash
git rm --cached config.json
```

Then verify:

```bash
git status
```

If a real password was ever committed to Git, changing the password is recommended. Removing the file in a later commit does not remove the secret from Git history.

---

# Troubleshooting

## `FRITZ_USER environment variable is required`

Load your `.env` file:

```bash
set -a
source .env
set +a
```

Then run the script again.

---

## `FRITZ_PASS environment variable is required`

Same solution:

```bash
set -a
source .env
set +a
```

Make sure `FRITZ_PASS` is defined in `.env`.

---

## FRITZ!Box login failed

Check:

```dotenv
FRITZ_HOST=http://fritz.box
FRITZ_USER=...
FRITZ_PASS=...
```

Also verify that the user has permission to access the FRITZ!Box Smart Home functions.

You can test basic connectivity:

```bash
curl http://fritz.box/login_sid.lua
```

The FRITZ!Box should return an XML response containing a challenge.

---

## No devices are detected

Run:

```bash
./detect_dect.sh
```

and verify that the output contains the expected FRITZ!DECT devices.

If the FRITZ!Box returns no devices, check the Smart Home configuration in the FRITZ!Box.

---

## Alexa cannot discover the devices

First check that Fauxmo is running:

```bash
docker ps
```

Then inspect the logs:

```bash
docker logs fritz-fauxmo
```

Make sure:

* the Echo and Docker host are on the same LAN
* the Docker container uses `--network host`
* the host firewall is not blocking local discovery
* the Fauxmo container is running continuously

Restarting device discovery from the Alexa app may also help.

---

## Alexa discovers the device but ON/OFF does not work

Check:

```bash
docker logs -f fritz-fauxmo
```

You should see requests similar to:

```text
[Desk Lamp] Turning ON
```

or:

```text
[Desk Lamp] Turning OFF
```

If authentication fails, verify that the container received the environment variables.

You can inspect the container environment without displaying the password:

```bash
docker exec fritz-fauxmo sh -c 'test -n "$FRITZ_USER" && echo "FRITZ_USER is set"'
```

and:

```bash
docker exec fritz-fauxmo sh -c 'test -n "$FRITZ_PASS" && echo "FRITZ_PASS is set"'
```

---

# Architecture details

## `detect_dect.sh`

Responsible for device discovery and configuration generation.

It communicates with the FRITZ!Box using:

```text
/login_sid.lua
```

for authentication and:

```text
/webservices/homeautoswitch.lua
```

for Smart Home device discovery.

It generates the Fauxmo configuration dynamically.

---

## `fritz_plugin.py`

Implements the Fauxmo plugin responsible for controlling the FRITZ!DECT devices.

It uses the FRITZ!Box AHA HTTP interface to:

* authenticate
* turn devices on
* turn devices off
* read the current switch state
* refresh the FRITZ!Box session when necessary

The plugin reads:

```text
FRITZ_USER
FRITZ_PASS
```

from environment variables.

---

## `Dockerfile`

Builds the Fauxmo runtime environment with:

* Python 3.12
* Fauxmo
* Requests
* the custom FRITZ!DECT plugin
* the generated Fauxmo configuration

---

## `run.sh`

Builds and starts the Docker container with:

```text
host networking
```

and passes the FRITZ!Box credentials to the container through environment variables.

---

# Development

To rebuild the container after changing the Python plugin:

```bash
./run.sh
```

To stop the container:

```bash
docker stop fritz-fauxmo
```

To remove it:

```bash
docker rm fritz-fauxmo
```

To rebuild manually:

```bash
docker build -t fritz-fauxmo .
```

---

# Project status

The current project provides a lightweight local bridge between:

```text
Amazon Alexa
       ↓
    Fauxmo
       ↓
 Python plugin
       ↓
  FRITZ!Box AHA
       ↓
 FRITZ!DECT
```

The main goal is to keep the integration simple, local and lightweight.

Future work may include exposing additional FRITZ!DECT capabilities, such as:

* temperature sensors
* energy consumption
* power measurements
* additional Alexa capabilities
* potentially an Alexa Smart Home Skill for sensor support

---

# License

Choose and add a license before publishing the project publicly.

For example, if you want a permissive open-source license, you can use the MIT License.

---

# Credits

This project uses [Fauxmo](https://github.com/n8henrie/fauxmo) to emulate compatible local smart-home devices for Alexa.

FRITZ!Box communication is based on the FRITZ!Box AHA HTTP interface.
