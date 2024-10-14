#!/bin/bash

# Step 1: Detect the current user and home directory
USER_HOME=$(eval echo ~$SUDO_USER)

# Step 2: Update the system and install required packages
sudo apt update && sudo apt upgrade -y
sudo apt install --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox chromium-browser unclutter python3-flask realvnc-vnc-server -y

# Step 3: Create the kiosk script (ensure the home directory exists)
mkdir -p "$USER_HOME"
cat <<EOL > "$USER_HOME/kiosk.sh"
#!/bin/bash
xset -dpms       # Disable Energy Star features
xset s off       # Disable screensaver
xset s noblank   # Disable screen blanking

# Hide the mouse cursor after 0.5 seconds of inactivity
unclutter -idle 0.5 &

# Launch Chromium in kiosk mode with the desired URL
chromium-browser --noerrdialogs --kiosk --disable-restore-session-state --disable-infobars --start-maximized "http://your-url-here"
EOL

# Make kiosk script executable
chmod +x "$USER_HOME/kiosk.sh"

# Step 4: Configure Openbox to run the kiosk script at startup (ensure Openbox config directory exists)
mkdir -p "$USER_HOME/.config/openbox"
echo "$USER_HOME/kiosk.sh &" >> "$USER_HOME/.config/openbox/autostart"

# Step 5: Enable auto-login for the current user
sudo raspi-config nonint do_boot_behaviour B4

# Step 6: Set up .bash_profile to start the X server automatically on login
if [ ! -f "$USER_HOME/.bash_profile" ]; then
  cat <<EOL >> "$USER_HOME/.bash_profile"
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  startx
fi
EOL
fi

# Step 7: Enable and configure Raspberry Pi Connect (VNC)
sudo raspi-config nonint do_vnc 0  # Enable VNC server
sudo systemctl enable vncserver-x11-serviced  # Ensure VNC starts on boot
sudo systemctl start vncserver-x11-serviced

# Step 8: Create the Kiosk Admin Panel using Flask

# Create the Flask app directory (ensure it exists)
mkdir -p "$USER_HOME/kiosk-admin/templates"

# Create the Flask app Python script (app.py)
cat <<EOL > "$USER_HOME/kiosk-admin/app.py"
from flask import Flask, render_template, request, redirect, url_for
import os

app = Flask(__name__)

# Path to the kiosk script
KIOSK_SCRIPT = "$USER_HOME/kiosk.sh"
WPA_SUPPLICANT_FILE = "/etc/wpa_supplicant/wpa_supplicant.conf"

# Render the admin page
@app.route('/')
def index():
    return render_template('index.html')

# Update Kiosk URL
@app.route('/update_url', methods=['POST'])
def update_url():
    new_url = request.form['kiosk_url']
    update_kiosk_url(new_url)
    return redirect(url_for('index'))

# Update WiFi Settings
@app.route('/update_wifi', methods=['POST'])
def update_wifi():
    ssid = request.form['ssid']
    password = request.form['password']
    update_wifi_config(ssid, password)
    return redirect(url_for('index'))

# Update Username
@app.route('/update_username', methods=['POST'])
def update_username():
    new_username = request.form['username']
    update_username_config(new_username)
    return redirect(url_for('index'))

# Function to update the kiosk URL
def update_kiosk_url(url):
    with open(KIOSK_SCRIPT, 'r') as file:
        lines = file.readlines()

    with open(KIOSK_SCRIPT, 'w') as file:
        for line in lines:
            if 'chromium-browser' in line:
                # Replace URL
                line = f'chromium-browser --noerrdialogs --kiosk --disable-restore-session-state --disable-infobars --start-maximized "{url}"\\n'
            file.write(line)

# Function to update Wi-Fi credentials
def update_wifi_config(ssid, password):
    with open(WPA_SUPPLICANT_FILE, 'w') as file:
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

# Function to change the username
def update_username_config(username):
    os.system(f"sudo usermod -l {username} pi")
    os.system(f"sudo usermod -d /home/{username} -m {username}")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOL

# Create the HTML template for the admin page
cat <<EOL > "$USER_HOME/kiosk-admin/templates/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kiosk Admin</title>
</head>
<body>
    <h1>Kiosk Admin Panel</h1>

    <!-- Form to update kiosk URL -->
    <h2>Update Kiosk URL</h2>
    <form action="/update_url" method="post">
        <label for="kiosk_url">Kiosk URL:</label>
        <input type="text" id="kiosk_url" name="kiosk_url" placeholder="http://your-url-here.com" required>
        <button type="submit">Update URL</button>
    </form>

    <!-- Form to update Wi-Fi credentials -->
    <h2>Update Wi-Fi</h2>
    <form action="/update_wifi" method="post">
        <label for="ssid">SSID:</label>
        <input type="text" id="ssid" name="ssid" placeholder="Wi-Fi SSID" required><br><br>
        <label for="password">Password:</label>
        <input type="password" id="password" name="password" placeholder="Wi-Fi Password" required>
        <button type="submit">Update Wi-Fi</button>
    </form>

    <!-- Form to update username -->
    <h2>Update Username</h2>
    <form action="/update_username" method="post">
        <label for="username">New Username:</label>
        <input type="text" id="username" name="username" placeholder="New Username" required>
        <button type="submit">Update Username</button>
    </form>
</body>
</html>
EOL

# Step 9: Create a systemd service to run Flask on boot
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

# Step 10: Reboot to apply all changes
sudo reboot
