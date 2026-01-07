# NSA LTE Redirect to EDGE PoC

This repository provides a complete **software-defined-radio** (SDR) environment to demonstrate network redirection from LTE (4G) to EDGE (2G) using **Osmocom** and **srsRAN_4G**.

## 🏗 Project Architecture

The solution is containerized to ensure all dependencies for the Osmocom stack and srsRAN are met without polluting the host system.

* 
**2G Stack**: Full Osmocom suite (MSC, BSC, HLR, GGSN, SGSN).


* 
**4G Stack**: srsEPC and srsENB.


* 
**Voice/SIP**: Asterisk integration for call routing.


* **Orchestration**: Automated via Tmux sessions inside the container.

## 🛠 Workflow & Usage

### 1. Build Phase

You can build the image manually or use the provided script. This stage compiles the entire Osmocom stack from source to ensure specific version compatibility.

```bash
chmod +x build.sh
./build.sh

```

### 2. Deployment Phase (The "Start" Script)

The `start.sh` script automates host-side network configuration and launches the container with the necessary privileges.

**It dynamically configures:**

* **IP Address**: Maps the services to your local network.
* **MCC / MNC**: Sets the Mobile Country and Network codes across all config files (`osmo-bsc.cfg`, `enb.conf`, etc.).
* **TAC**: Sets the Tracking Area Code for the LTE cell.

```bash
sudo ./start.sh

```

### 3. Development Workflow

If you are modifying the source code or configurations:

1. **Modify** the files in the `configs/` or `scripts/` directories.
2. **Re-run** `./start.sh` (The script uses `sed` to inject your variables into the local files before the Docker build/copy process).
3. **Attach** to the running container to debug:
```bash
docker exec -it egprs tmux attach-session -t osmocom

```



## 📂 Key Components

| Component | Description | Source |
| --- | --- | --- |
| `Dockerfile` | Multi-stage build for Osmocom and srsRAN.

 | Source 

 |
| `start.sh` | Host setup (TUN/TAP, IP routing, User prompts). | User Script |
| `run.sh` | Internal container orchestrator (Starts services in Tmux). | User Script |
| `configs/` | Template configuration files for all network nodes.

 | Source 

 |

I will add this critical technical distinction to your documentation. It is a vital point for anyone testing **software-defined-radio** redirections, as the behavior of Tier-1 operators (MNOs) differs significantly from virtual operators (MVNOs).

---

### Updated "Technical Notes" Section for README

Add this section to your README to warn users about the fallback behavior:

## 📡 Network Compatibility & Fallback Behavior

### MNO vs. MVNO

While this PoC demonstrates the redirection mechanism, its effectiveness depends on the target network's core configuration:

* 
**MVNOs (Mobile Virtual Network Operators):** Generally more susceptible to remaining on the redirected EDGE/GSM layer once the handover or redirection is triggered. 


* **MNOs (Mobile Network Operators):** Most Tier-1 operators have aggressive **Fast Return to LTE** or **LTE Steering** policies. In many cases, even if a redirection to EDGE is successful, the UE (User Equipment) will only stay on the 2G layer for a very short duration before the network or the SIM card forces a fallback/reselection to 4G/NSA. 



### Redirection Mechanism

The project uses a patched version of `srsRAN_4G` to trigger the redirection. It relies on specific RRC (Radio Resource Control) release messages with redirection information to force the phone to scan the GSM frequencies defined in your `osmo-bsc` configuration. 


## ⚠️ Requirements & Safety

* 
**Privileged Mode**: Docker must run with `--privileged` to access SDR hardware (USRP/BladeRF) and manage network interfaces.


* **Legal**: This PoC is for educational purposes. Always use a Faraday cage when transmitting on cellular frequencies.
