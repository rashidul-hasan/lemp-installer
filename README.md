# LEMP Stack Installer & Manager

An interactive bash script to easily install, manage, and uninstall LEMP stack (Linux, Nginx, MySQL, PHP, Composer) on Ubuntu/Debian systems.

## Features

- 🎯 **Interactive Menu** - No need to remember command-line arguments
- ✅ **Smart Installation** - Checks if components are already installed before proceeding
- 🗑️ **Uninstall Support** - Completely remove any or all LEMP components
- 🎨 **Color-coded Output** - Easy-to-read status messages
- 🔍 **Status Checker** - View installation status of all components
- 🔒 **Safe Operations** - Confirmation prompts for destructive actions
- 📦 **Multiple PHP Versions** - Support for PHP 7.4, 8.0, 8.1, 8.2, 8.3, and custom versions
- 🧩 **Modular Installation** - Install only the services you need (Nginx, MySQL, PHP, or Composer)
- 🌐 **Nginx Domain Config** - Create Laravel-optimized Nginx configurations for new domains
- 🔒 **SSL Ready** - Installs Certbot Nginx plugin for easy Let's Encrypt SSL setup

## Requirements

- Ubuntu or Debian-based Linux distribution
- sudo privileges
- Internet connection

## Installation

1. Download the script:

```bash
wget https://raw.githubusercontent.com/rashidul-hasan/lemp-installer/main/lemp-installer.sh
```

2. Make it executable:

```bash
chmod +x lemp-installer.sh
```

3. Run the script:

```bash
./lemp-installer.sh
```

## Usage

Simply run the script and follow the interactive prompts:

```bash
./lemp-installer.sh
```

### Main Menu Options

1. **Install Full LEMP Stack** - All-in-one installation
2. **Install Specific Components** - Choose individual services to install
3. **Uninstall Components** - Remove specific components or entire stack
4. **Check Installation Status** - View what's currently installed
5. **Create Nginx Domain Config** - Setup a new domain with a Laravel-optimized Nginx config
6. **Exit** - Close the script

### Installing LEMP Stack

When you choose to install, the script will:

- Update package lists
- Install Nginx (if not already installed)
- Install MySQL with secure setup prompts
- Install your chosen PHP version with common extensions
- Install Composer (if not already installed)

### PHP Installation

The script supports multiple PHP versions:

- PHP 7.4
- PHP 8.0
- PHP 8.1
- PHP 8.2
- PHP 8.3
- Custom version

**Included PHP Extensions:**

- php-fpm
- php-mysql
- php-xml
- php-gd
- php-curl
- php-mbstring
- php-zip
- php-bcmath
- php-intl

### MySQL Setup

During MySQL installation, you'll be prompted to:

- Set a root username
- Set a root password
- Optionally create databases

The script automatically:

- Removes anonymous users
- Disables remote root login
- Removes test database
- Secures the installation

### Uninstalling Components

The uninstall menu allows you to remove:

- **Nginx** - Removes Nginx and all configuration files
- **MySQL** - ⚠️ Removes MySQL and ALL databases (backup first!)
- **PHP** - Choose specific version or remove all versions
- **Composer** - Removes Composer binary
- **Everything** - Complete LEMP stack removal

### Nginx Domain Configuration

When creating a new domain configuration, the script will:

- Ask for the domain name
- Ask for the web root directory (defaults to `/var/www/domain/public`)
- Ask for the PHP version to use
- Create a Laravel-optimized Nginx configuration file
- Enable the configuration and reload Nginx
- Provide the command to get an SSL certificate via Certbot

## What Gets Installed

| Component           | Package                          |
| ------------------- | -------------------------------- |
| **Web Server**      | Nginx & Certbot Plugin           |
| **Database**        | MySQL 8.0                        |
| **PHP**             | Your chosen version (7.4 - 8.3+) |
| **Package Manager** | Composer (latest)                |

## Screenshots

### Main Menu

```
======================================
   LEMP Stack Installer & Manager
======================================

1) Install Full LEMP Stack
2) Install Specific Components
3) Uninstall Components
4) Check Installation Status
5) Create Nginx Domain Config
6) Exit
```

### Installation Status

```
======================================
   Installation Status
======================================

[SUCCESS] Nginx: Installed (1.24.0)
[SUCCESS] MySQL: Installed (8.0.35)
[SUCCESS] PHP: Installed
  Versions: 8.2
[SUCCESS] Composer: Installed (2.6.5)
```

## Safety Features

- ✅ Prevents running as root
- ✅ Checks for supported distributions (Ubuntu/Debian only)
- ✅ Confirms before destructive operations
- ✅ Skips already installed components
- ✅ Strong warnings for data-destructive operations
- ✅ Requires typing "DELETE EVERYTHING" to remove entire stack

## Troubleshooting

### Script won't run

```bash
# Make sure it's executable
chmod +x lemp-installer.sh

# Check if you're on Ubuntu/Debian
cat /etc/os-release
```

### PHP version not installing

- The script uses Ondrej's PPA repository
- Some older PHP versions may not be available on newer Ubuntu releases
- Try a more recent PHP version

### MySQL password issues

- Make sure to remember the password you set
- Password is required for database creation
- Cannot be recovered if forgotten (requires MySQL reinstall)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - feel free to use and modify as needed.

## Author

**Rashidul** - [rashidul69@gmail.com](mailto:rashidul69@gmail.com)

## Changelog

### Version 2.2

- Added modular installation support (install individual components)
- Reorganized main menu for better usability

### Version 2.1

- Added Nginx domain configuration for Laravel applications
- Added Certbot Nginx plugin installation by default
- Updated README with new features and usage instructions

### Version 2.0

- Added interactive menu system
- Added installation status checking
- Added uninstall functionality
- Added support for multiple PHP versions
- Added color-coded output
- Added Linux distribution validation
- Improved error handling
- Better PHP version control

### Version 1.0

- Initial release with command-line arguments

## Support

If you encounter any issues or have questions, please open an issue on GitHub.

---

⭐ If you find this script useful, please give it a star on GitHub!
