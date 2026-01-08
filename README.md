# NSA LTE Redirect to EDGE PoC

This repository provides a complete **software-defined-radio** environment to demonstrate network redirection from LTE (4G) to EDGE (2G) using **Osmocom** and a patched version of **srsRAN_4G**.

## 🏗 Project Architecture

The solution is containerized to manage the complex dependencies of the Osmocom and srsRAN stacks.

* **2G Stack (MVNO Identity)**: Full Osmocom suite (MSC, BSC, HLR, GGSN, SGSN).


* **4G Stack (MNO Identity)**: srsEPC and srsENB serving as the LTE anchor.


* **Voice/SIP**: Asterisk integration for mobile-to-SIP routing.


* **Orchestration**: Automated via Tmux sessions inside the container for real-time monitoring.

## 🛠 Workflow & Usage

### 1. Build Phase

Compile the Osmocom stack and srsRAN from source to ensure specific version compatibility.

```bash
chmod +x build.sh
./build.sh

```

OR

Grab the docker build 

```bash
sudo docker pull ghcr.io/bbaranoff/nsa_lte_redirect_to_edge:main
sudo docker tag ghcr.io/bbaranoff/nsa_lte_redirect_to_edge:main redirection_build
```

### 2. Deployment Phase (`start.sh`)

The `start.sh` script automates host configuration and uses a dual-prompt system to handle network identities.

**It dynamically configures:**

* **Host IP**: Maps services to your local network via global `sed` replacement.
* **MNO (LTE Anchor)**: Injects the MNO MCC/MNC into `enb.conf` and `epc.conf` so the UE attaches to your LTE cell.
* **MVNO (Redirection Target)**: Injects the MVNO MCC/MNC into `osmo-bsc.cfg` and `osmo-msc.cfg` for the EDGE cell.
* **TAC**: Sets the Tracking Area Code for the LTE cell.

```bash
sudo ./start.sh

```

### 3. Development Workflow

1. **Modify**: Edit files in `configs/` or `scripts/` locally.


2. **Inject**: The `start.sh` script applies your MCC/MNC/IP variables to local files before the Docker build/copy process.


3. **Monitor**: Attach to the Tmux session to see real-time interaction between the eNodeB and the BTS:

```bash
docker exec -it egprs tmux attach-session -t osmocom

```

## 📡 Network Compatibility & Fallback Behavior

### MNO vs. MVNO

Seems working on (any?) MNVO and (any?) phones put the MNO MCC/MNC in the eNodeB and the MNVO MCC/MNC in the BTS, the tac should be +/-1 than the genuine one. The EARFCN should be the same than the genuine eNodeB.

Once the UE is redirected and attaches to the 2G MVNO cell, it remains on the EDGE network because it does not recognize any available 4G cells sharing the specific MVNO identifiers. The device stops searching for LTE layers since the broadcasted PLMN on the 2G side does not match the MNO's 4G neighbor list. By isolating the MVNO identity on the 2G stack, you effectively prevent the handset from triggering a fast-return to the 4G anchor.

The effectiveness of the redirection depends on the target network's core policy:

* **MVNOs (Mobile Virtual Network Operators)**: Generally more stable for testing as they are more likely to remain on the redirected EDGE layer.
* **MNOs (Mobile Network Operators)**: Most Tier-1 operators use aggressive **Fast Return to LTE** or **LTE Steering**. On MNOs, the UE may only stay on 2G for a very short duration before the network or SIM card forces a fallback to 4G/NSA.

### Redirection Mechanism

The project uses a patched version of `srsRAN_4G`. It triggers specific RRC (Radio Resource Control) release messages with redirection info, forcing the UE to scan the GSM frequencies defined in the `osmo-bsc` configuration.

## 📂 Key Components

| Component | Description |
| --- | --- |
| `Dockerfile` | Multi-stage build for Osmocom and srsRAN. |
| `start.sh` | Host setup (TUN/TAP, IP routing) and Dual-ID prompts. |
| `run.sh` | Internal orchestrator starting services in Tmux. |
| `configs/` | Template configuration files for all network nodes. |

## ⚠️ Requirements & Safety

* **Privileged Mode**: Docker must run with `--privileged` to access SDR hardware and manage network interfaces.
* **Legal**: This PoC is for educational purposes only. Always use a Faraday cage when transmitting on cellular frequencies.
