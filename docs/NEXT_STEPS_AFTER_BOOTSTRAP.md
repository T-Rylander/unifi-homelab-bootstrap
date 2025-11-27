# Next Steps After Running This Bootstrap Repo

You have just:
- Installed a clean UniFi Network Controller on Ubuntu
- Factory-reset and adopted all devices
- Everything is on the default 192.168.1.0/24 corporate network

**You are now ready to run the declarative overhaul repo**

1. Clone the declarative repo
   ```bash
   sudo mkdir -p /opt && cd /opt
   sudo git clone https://github.com/T-Rylander/unifi-declarative-network.git
   sudo chown -R $USER:$USER unifi-declarative-network
   cd unifi-declarative-network
   ```

2. Create a local-only, no-2FA admin account in the UniFi GUI
   - Settings → Admins → Add Admin → Local Access Only → uncheck 2FA

3. Run the declarative apply (it will create all VLANs + keep 192.168.1.0/24 alive)
   ```bash
   python3 -m venv venv && source venv/bin/activate
   pip install -r requirements.txt
   nano .env   # ← put the no-2FA account credentials + UNIFI_VERIFY_SSL=false
   ./venv/bin/python -m src.unifi_declarative.apply
   ```

4. Then follow the migration steps in the declarative repo’s MIGRATION_GUIDE.md

**This is the ONLY supported path forward.**
