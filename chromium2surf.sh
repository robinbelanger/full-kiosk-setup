#!/bin/bash

# Step 1: Update the system and install necessary packages
echo "Updating the system and installing Surf browser..."
sudo apt update
sudo apt upgrade -y
sudo apt install surf -y  # Install Surf, a lightweight browser

# Step 2: Create the Kiosk Script to Run Surf in Kiosk Mode
echo "Creating kiosk script..."
KIOSK_SCRIPT="/home/robin/kiosk-admin/surf_kiosk.sh"

# Create the kiosk-admin directory if it doesn't exist
mkdir -p /home/robin/kiosk-admin

# Write the kiosk script
cat <<EOL > $KIOSK_SCRIPT
#!/bin/bash
export DISPLAY=:0
echo "Starting Kiosk Script" >> /home/robin/kiosk.log
xset -dpms  # Disable DPMS (Energy Star) features
xset s off  # Disable screensaver
xset s noblank  # Disable screen blanking

# Launch Surf in fullscreen kiosk mode
echo "Launching Surf" >> /home/robin/kiosk.log
surf -F "http://your-url-here" >> /home/robin/kiosk.log 2>&1
EOL

# Make the kiosk script executable
chmod +x $KIOSK_SCRIPT
echo "Kiosk script created at $KIOSK_SCRIPT."

# Step 3: Set Up a Systemd Service to Run the Kiosk Script at Boot
echo "Setting up systemd service..."
SERVICE_FILE="/etc/systemd/system/kiosk.service"

# Create the systemd service file
sudo bash -c "cat <<EOL > $SERVICE_FILE
[Unit]
Description=Kiosk Mode Browser
After=graphical.target

[Service]
Environment=DISPLAY=:0
User=robin
ExecStart=/home/robin/kiosk-admin/surf_kiosk.sh
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOL"

# Reload systemd to apply the new service
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable kiosk.service

# Start the kiosk service now to test it
sudo systemctl start kiosk.service

# Step 4: Adjust Permissions (if needed)
echo "Adjusting permissions for /home/robin/kiosk-admin/..."
sudo chown -R robin:robin /home/robin/kiosk-admin/
sudo chmod +x /home/robin/kiosk-admin/surf_kiosk.sh

# Step 5: Provide Feedback to User
echo "Kiosk setup complete. The Surf browser should now start automatically in fullscreen on boot."
echo "Check the log file at /home/robin/kiosk.log if you encounter any issues."

# Step 6: Optional - Reboot for the changes to take effect
read -p "Reboot now to apply all changes? (y/n): " REBOOT
if [ "$REBOOT" == "y" ]; then
    sudo reboot
else
    echo "Reboot later to apply all changes."
fi
