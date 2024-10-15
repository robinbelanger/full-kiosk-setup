#!/bin/bash

# Step 1: Detect the current user and home directory
USER_HOME=$(eval echo ~$SUDO_USER)

# Step 2: Update the system and install necessary packages (chromium-lite and selenium for automation)
sudo apt update && sudo apt upgrade -y
sudo apt install --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox unclutter python3-flask chromium-lite python3-selenium -y

# Step 3: Create the kiosk script for Chromium Lite (ensure the home directory exists)
mkdir -p "$USER_HOME"
cat <<EOL > "$USER_HOME/kiosk.sh"
#!/bin/bash
xset -dpms       # Disable Energy Star features
xset s off       # Disable screensaver
xset s noblank   # Disable screen blanking

# Hide the mouse cursor after 0.5 seconds of inactivity
unclutter -idle 0.5 &

# Launch Chromium Lite in kiosk mode with Selenium automation
python3 $USER_HOME/kiosk-admin/kiosk_automation.py
EOL

# Make kiosk script executable
chmod +x "$USER_HOME/kiosk.sh"

# Step 4: Configure Openbox to run the kiosk script at startup
mkdir -p "$USER_HOME/.config/openbox"
echo "$USER_HOME/kiosk.sh &" >> "$USER_HOME/.config/openbox/autostart"

# Step 5: Set up .bash_profile to start the X server automatically on login
if [ ! -f "$USER_HOME/.bash_profile" ]; then
  cat <<EOL >> "$USER_HOME/.bash_profile"
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  startx
fi
EOL
fi

# Step 6: Enable and configure Raspberry Pi Connect (VNC)
sudo raspi-config nonint do_vnc 0  # Enable VNC server
sudo systemctl enable vncserver-x11-serviced  # Ensure VNC starts on boot
sudo systemctl start vncserver-x11-serviced

# Step 7: Create the Kiosk Admin Panel using Flask

# Create the Flask app directory (ensure it exists)
mkdir -p "$USER_HOME/kiosk-admin/templates"

# Create the Flask app Python script (app.py)
cat <<EOL > "$USER_HOME/kiosk-admin/app.py"
from flask import Flask, render_template, request, redirect, url_for
import os, subprocess, time

app = Flask(__name__)

# Path to the kiosk script
KIOSK_SCRIPT = "$USER_HOME/kiosk.sh"
WPA_SUPPLICANT_FILE = "/etc/wpa_supplicant/wpa_supplicant.conf"

# Load current URL
def get_current_url():
    with open(KIOSK_SCRIPT, 'r') as file:
        for line in file:
            if 'chromium-lite' in line:
                return line.split('"')[1]
    return None

# Load current WiFi SSID
def get_current_ssid():
    with open(WPA_SUPPLICANT_FILE, 'r') as file:
        for line in file:
            if 'ssid' in line:
                return line.split('"')[1]
    return None

# Render the admin page
@app.route('/')
def index():
    current_url = get_current_url()
    current_ssid = get_current_ssid()
    return render_template('index.html', current_url=current_url, current_ssid=current_ssid)

# Update Kiosk URL
@app.route('/update_url', methods=['POST'])
def update_url():
    new_url = request.form['kiosk_url']
    update_kiosk_url(new_url)
    return redirect(url_for('index'))

def update_kiosk_url(url):
    with open(KIOSK_SCRIPT, 'r') as file:
        lines = file.readlines()

    with open(KIOSK_SCRIPT, 'w') as file:
        for line in lines:
            if 'chromium-lite' in line:
                line = f'chromium-lite --kiosk "{url}"\n'
            file.write(line)

# Update Wi-Fi credentials with fallback
@app.route('/update_wifi', methods=['POST'])
def update_wifi():
    ssid = request.form['ssid']
    password = request.form['password']
    prev_ssid = get_current_ssid()

    # Write the new config to a temporary file
    temp_file = '/tmp/wpa_supplicant.conf'
    with open(temp_file, 'w') as file:
        file.write(f"""
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={{
    ssid="{ssid}"
    psk="{password}"
    key_mgmt=WPA-PSK
}}
""")

    # Apply the new Wi-Fi settings
    subprocess.run(['sudo', 'mv', temp_file, WPA_SUPPLICANT_FILE], check=True)
    subprocess.run(['sudo', 'systemctl', 'restart', 'wpa_supplicant'], check=True)

    # Wait 60 seconds to confirm connection, otherwise revert
    time.sleep(60)
    new_ssid = get_current_ssid()
    if new_ssid != ssid:
        # Fallback to previous SSID
        print("Failed to connect. Reverting to previous SSID.")
        update_wifi_config(prev_ssid, password)
        subprocess.run(['sudo', 'systemctl', 'restart', 'wpa_supplicant'], check=True)

    return redirect(url_for('index'))

# Update hostname and reboot
@app.route('/update_hostname', methods=['POST'])
def update_hostname():
    new_hostname = request.form['hostname']
    subprocess.run(['sudo', 'hostnamectl', 'set-hostname', new_hostname], check=True)
    subprocess.run(['sudo', 'reboot'], check=True)
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOL

# Create the HTML template for the admin page with Bootstrap
cat <<EOL > "$USER_HOME/kiosk-admin/templates/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kiosk Admin</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body>
    <div class="container mt-5">
        <h1>Kiosk Admin Panel</h1>
        
        <h2>Update Kiosk URL</h2>
        <p>Current URL: <strong>{{ current_url }}</strong></p>
        <form action="/update_url" method="post">
            <input class="form-control mb-3" type="text" id="kiosk_url" name="kiosk_url" placeholder="http://your-url-here.com" required>
            <button class="btn btn-primary" type="submit">Update URL</button>
        </form>

        <h2>Klinik Path</h2>
        <form id="klinikForm">
            <input class="form-control mb-3" type="text" id="klinik_id" name="klinik_id" placeholder="Enter Klinik" required>
            <button class="btn btn-primary" id="submitButton" type="submit">Update Klinik</button>
        </form>

        <h2>Update Wi-Fi</h2>
        <p>Current SSID: <strong>{{ current_ssid }}</strong></p>
        <form action="/update_wifi" method="post">
            <input class="form-control mb-3" type="text" id="ssid" name="ssid" placeholder="SSID" required>
            <input class="form-control mb-3" type="password" id="password" name="password" placeholder="Password" required>
            <button class="btn btn-primary" type="submit">Update Wi-Fi</button>
        </form>

        <h2>Update Hostname</h2>
        <form action="/update_hostname" method="post">
            <input class="form-control mb-3" type="text" id="hostname" name="hostname" placeholder="New Hostname" required>
            <button class="btn btn-primary" type="submit">Update Hostname and Reboot</button>
        </form>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOL

# Step 8: Create a systemd service to run Flask on boot
sudo tee /etc/systemd/system/kiosk-admin.service > /dev/null <<EOL
[Unit]
Description=Kiosk Admin Web Interface
After=network.target

[Service]
ExecStart=/usr/bin/python3 $USER_HOME/kiosk-admin/app.py
WorkingDirectory=$USER_HOME/kiosk-admin
User=$SUDO_USER
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Enable and start the Kiosk Admin service
sudo systemctl enable kiosk-admin
sudo systemctl start kiosk-admin

# Step 9: Reboot to apply all changes
sudo reboot
