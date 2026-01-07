# NSA LTE Redirect to EDGE PoC

This repository provides a complete **software-defined-radio** environment to demonstrate network redirection from LTE (4G) to EDGE (2G) using **Osmocom** and **srsRAN_4G**.

## 🏗 Project Architecture

The solution is containerized using a Ubuntu 22.04 base to ensure all dependencies are met without polluting the host system.

* **2G Stack**: Full Osmocom suite including `osmo-msc`, `osmo-bsc`, `osmo-hlr`, `osmo-ggsn`, and `osmo-sgsn`.


* **4G Stack**: Integrated `srsRAN_4G` suite providing eNodeB and EPC capabilities.


* **Voice/SIP**: Asterisk integration for call routing via `osmo-sip-connector`.


* **Radio Interface**: Support for `osmo-trx-uhd` to interface with hardware and `osmo-bts-virtual` for testing.


* **Orchestration**: Automated service management via Systemd and Tmux sessions inside the container.



## 🛠 Workflow & Usage

### 1. Build Phase

The build process compiles the entire Osmocom stack and srsRAN from source to ensure version compatibility.

```bash
# Manual build using the provided Dockerfile
docker build -t redirection_poc .

```

### 2. Deployment Phase (`start.sh`)

The `start.sh` script automates host-side network configuration and launches the container with necessary privileges.
**It dynamically configures:**

* **IP Address**: Maps services to your local network via global `sed` replacement.
* **MCC / MNC**: Sets Mobile Country/Network codes in `osmo-bsc.cfg`, `osmo-msc.cfg`, and srsRAN `.conf` files.
* **TAC**: Sets the Tracking Area Code for the LTE cell in `epc.conf`.

### 3. Development Workflow

1. **Modify**: Update files in `configs/` or `scripts/` locally.


2. **Inject & Run**: The `start.sh` script uses `sed` to inject variables before the Docker build/copy process.


3. **Debug**: Attach to the Tmux session to monitor real-time logs:

```bash
docker exec -it egprs tmux attach-session -t osmocom

```

## 📡 Network Compatibility & Fallback Behavior

### MNO vs. MVNO

The effectiveness of this PoC depends heavily on the target network's core configuration:

* **MVNOs (Mobile Virtual Network Operators)**: Generally more susceptible to remaining on the redirected EDGE/GSM layer.
* **MNOs (Mobile Network Operators)**: Most Tier-1 operators use aggressive **Fast Return to LTE** or **LTE Steering** policies. On MNOs, the UE may only stay on 2G for a very short duration before the network or SIM card forces a fallback to 4G/NSA.

### Redirection Mechanism

The project uses a patched version of `srsRAN_4G`. It relies on specific RRC (Radio Resource Control) release messages to force the UE to scan the GSM frequencies defined in the `osmo-bsc` configuration.

## 📂 Key Components

| Component | Description |
| --- | --- |
| `Dockerfile` | Multi-stage build for Osmocom and srsRAN. |
| `start.sh` | Host setup (TUN/TAP, IP routing) and user prompts. | 
| `run.sh` | Container orchestrator starting services in Tmux. |
| `configs/` | Template configuration files for all network nodes. | 


## ⚠️ Requirements & Safety

* **Privileged Mode**: Docker must run with `--privileged` and `--net host` to access SDR hardware and manage network interfaces.


* **Legal**: This PoC is for educational purposes only. Always use a Faraday cage when transmitting on cellular frequencies.
