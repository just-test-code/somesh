**Server Cleanup**

This script will help you to clean up your server by removing all the unnecessary files and directories.

## Interactive Menu

You can use the interactive menu to select the cleanup options.

```sh
bash <(curl -s https://raw.githubusercontent.com/JustTestCode/somesh/main/debian.sh)
```

### Usage

#### Method 1: Interactive Menu (Recommended)
Run the script and use the up and down arrow keys to select the options:
```sh
bash debian.sh
```

#### Method 2: Command Line Arguments
Specify the options to run:
```sh
bash debian.sh option1 option2  # You can run multiple options at once
```

#### Online Installation (Automatically downloads the latest version)
```sh
bash <(curl -s https://raw.githubusercontent.com/JustTestCode/somesh/main/debian.sh)
```

### SSH Configuration Explanation
After selecting the "Configure SSH" option, you will need to input your SSH public key. The public key is usually located at:
- Windows: `C:\Users\your_username\.ssh\id_ed25519.pub` or `id_rsa.pub`
- Linux/Mac: `~/.ssh/id_ed25519.pub` or `id_rsa.pub`

If you don't have an SSH key pair, you can generate one using the following commands:
```sh
# Generate ED25519 key (Recommended)
ssh-keygen -t ed25519 -C "your_email@example.com"

# Or generate RSA key
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

### Hostname Modification Explanation
After selecting the "Modify Hostname" option, you will need to input the new hostname. The hostname rules are:
- Can only contain letters, numbers, and hyphens (-)
- Cannot be empty
- It is recommended to use a meaningful name, such as: web-server-01