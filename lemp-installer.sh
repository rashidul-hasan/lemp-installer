#!/bin/bash

# LEMP Stack Installer & Manager
# Author: Rashidul <rashidul69@gmail.com>
# Enhanced version with interactive prompts and uninstall options

set -e

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if Nginx is installed
is_nginx_installed() {
    dpkg -l | grep -q "^ii.*nginx" 2>/dev/null
}

# Function to check if MySQL is installed
is_mysql_installed() {
    dpkg -l | grep -q "^ii.*mysql-server" 2>/dev/null
}

# Function to check if PHP is installed
is_php_installed() {
    local version=$1
    dpkg -l | grep -q "^ii.*php${version}-fpm" 2>/dev/null
}

# Function to check if Composer is installed
is_composer_installed() {
    command_exists composer
}

# Function to get installed PHP versions
get_installed_php_versions() {
    dpkg -l | grep "^ii.*php[0-9].*-fpm" | awk '{print $2}' | grep -oP 'php\K[0-9]+\.[0-9]+' | sort -u
}

# Function to display main menu
show_main_menu() {
    clear
    echo "======================================"
    echo "   LEMP Stack Installer & Manager"
    echo "======================================"
    echo ""
    echo "1) Install LEMP Stack"
    echo "2) Uninstall Components"
    echo "3) Check Installation Status"
    echo "4) Exit"
    echo ""
}

# Function to check and display installation status
check_installation_status() {
    clear
    echo "======================================"
    echo "   Installation Status"
    echo "======================================"
    echo ""
    
    if is_nginx_installed; then
        print_success "Nginx: Installed ($(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+'))"
    else
        print_warning "Nginx: Not installed"
    fi
    
    if is_mysql_installed; then
        print_success "MySQL: Installed ($(mysql --version 2>/dev/null | grep -oP 'Distrib \K[0-9.]+' || echo 'unknown version'))"
    else
        print_warning "MySQL: Not installed"
    fi
    
    local php_versions=$(get_installed_php_versions)
    if [ -n "$php_versions" ]; then
        print_success "PHP: Installed"
        echo "  Versions: $php_versions"
    else
        print_warning "PHP: Not installed"
    fi
    
    if is_composer_installed; then
        print_success "Composer: Installed ($(composer --version 2>/dev/null | grep -oP 'Composer version \K[0-9.]+' || echo 'unknown version'))"
    else
        print_warning "Composer: Not installed"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Function to install Nginx
install_nginx() {
    if is_nginx_installed; then
        print_warning "Nginx is already installed. Skipping..."
        return 0
    fi
    
    print_info "Installing Nginx..."
    sudo apt install nginx -y
    print_success "Nginx installed successfully!"
}

# Function to install MySQL
install_mysql() {
    if is_mysql_installed; then
        print_warning "MySQL is already installed. Skipping..."
        return 0
    fi
    
    print_info "Installing MySQL..."
    sudo apt install mysql-server -y
    
    # Prompt for MySQL configuration
    echo ""
    print_info "MySQL Configuration"
    read -p "Enter MySQL root username: " MYSQL_ROOT_USER
    read -sp "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
    echo ""
    
    # Run mysql_secure_installation steps
    print_info "Securing MySQL installation..."
    
    sudo mysql <<EOF
    -- Create a new user with root privileges
    CREATE USER IF NOT EXISTS '$MYSQL_ROOT_USER'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
    GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_ROOT_USER'@'localhost' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
    -- Remove root user
    DELETE FROM mysql.user WHERE User='root' AND Host='localhost';
    -- Remove anonymous users
    DELETE FROM mysql.user WHERE User='';
    -- Disallow root login remotely
    DELETE FROM mysql.user WHERE User='$MYSQL_ROOT_USER' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    -- Remove test database and access to it
    DROP DATABASE IF EXISTS test;
    DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
    -- Reload privilege tables
    FLUSH PRIVILEGES;
EOF
    
    print_success "MySQL secured successfully!"
    
    # Ask if user wants to create databases
    echo ""
    read -p "Do you want to create databases now? (y/n): " create_dbs
    if [[ "$create_dbs" =~ ^[Yy]$ ]]; then
        read -p "Enter database names (comma-separated, e.g., db1,db2): " MYSQL_DATABASES
        
        if [ -n "$MYSQL_DATABASES" ]; then
            IFS=',' read -r -a DB_ARRAY <<< "$MYSQL_DATABASES"
            for DB_NAME in "${DB_ARRAY[@]}"; do
                # Trim whitespace
                DB_NAME=$(echo "$DB_NAME" | xargs)
                mysql --user="$MYSQL_ROOT_USER" --password="$MYSQL_ROOT_PASSWORD" <<EOF
                CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
                GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$MYSQL_ROOT_USER'@'localhost';
                FLUSH PRIVILEGES;
EOF
                print_success "Database '$DB_NAME' created and privileges granted."
            done
        fi
    fi
}

# Function to install PHP
install_php() {
    echo ""
    print_info "PHP Installation"
    
    # Show available PHP versions
    echo "Available PHP versions:"
    echo "1) PHP 7.4"
    echo "2) PHP 8.0"
    echo "3) PHP 8.1"
    echo "4) PHP 8.2"
    echo "5) PHP 8.3"
    echo "6) Custom version"
    
    read -p "Select PHP version (1-6): " php_choice
    
    case $php_choice in
        1) PHP_VERSION="7.4" ;;
        2) PHP_VERSION="8.0" ;;
        3) PHP_VERSION="8.1" ;;
        4) PHP_VERSION="8.2" ;;
        5) PHP_VERSION="8.3" ;;
        6) read -p "Enter custom PHP version (e.g., 8.2): " PHP_VERSION ;;
        *) print_error "Invalid choice. Defaulting to PHP 8.1"; PHP_VERSION="8.1" ;;
    esac
    
    if is_php_installed "$PHP_VERSION"; then
        print_warning "PHP $PHP_VERSION is already installed. Skipping..."
        return 0
    fi
    
    # Add Ondrej PHP repository
    print_info "Adding PHP repository..."
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt update
    
    # Install PHP and extensions with explicit version
    print_info "Installing PHP $PHP_VERSION and extensions..."
    
    # First, install php-fpm for the specific version
    if ! sudo apt install -y "php${PHP_VERSION}-fpm"; then
        print_error "Failed to install PHP ${PHP_VERSION}-fpm. The version might not be available."
        return 1
    fi
    
    # Then install extensions
    local extensions=(
        "mysql"
        "xml"
        "gd"
        "curl"
        "mbstring"
        "zip"
        "bcmath"
        "intl"
    )
    
    print_info "Installing PHP extensions..."
    for ext in "${extensions[@]}"; do
        local package="php${PHP_VERSION}-${ext}"
        if sudo apt install -y "$package"; then
            print_success "Installed $package"
        else
            print_warning "Failed to install $package (might not be available)"
        fi
    done
    
    # Set the installed version as default if multiple versions exist
    print_info "Setting PHP $PHP_VERSION as default..."
    sudo update-alternatives --set php /usr/bin/php${PHP_VERSION} 2>/dev/null || true
    
    print_success "PHP $PHP_VERSION installed successfully!"
    echo "Active PHP version: $(php -v | head -n 1)"
    
    # Show PHP-FPM service status
    local fpm_service="php${PHP_VERSION}-fpm"
    if systemctl is-active --quiet "$fpm_service"; then
        print_success "PHP-FPM service is running"
    else
        print_info "Starting PHP-FPM service..."
        sudo systemctl start "$fpm_service"
        sudo systemctl enable "$fpm_service"
    fi
}

# Function to install Composer
install_composer() {
    if is_composer_installed; then
        print_warning "Composer is already installed. Skipping..."
        return 0
    fi
    
    print_info "Installing Composer..."
    sudo apt install -y php-cli unzip
    
    cd /tmp
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php
    
    print_success "Composer installed successfully!"
    echo "Composer version: $(composer --version)"
}

# Function to install LEMP stack
install_lemp() {
    clear
    echo "======================================"
    echo "   LEMP Stack Installation"
    echo "======================================"
    echo ""
    
    print_info "This will install Nginx, MySQL, PHP, and Composer."
    echo ""
    read -p "Do you want to proceed? (y/n): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Installation cancelled."
        return
    fi
    
    # Update package lists
    print_info "Updating package lists..."
    sudo apt update
    
    # Install components
    install_nginx
    echo ""
    install_mysql
    echo ""
    install_php
    echo ""
    install_composer
    echo ""
    
    print_success "LEMP stack installation completed!"
    echo ""
    read -p "Press Enter to continue..."
}

# Function to uninstall Nginx
uninstall_nginx() {
    if ! is_nginx_installed; then
        print_warning "Nginx is not installed."
        return 0
    fi
    
    print_warning "This will completely remove Nginx and its configuration files."
    read -p "Are you sure? (y/n): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Uninstalling Nginx..."
        sudo systemctl stop nginx 2>/dev/null || true
        sudo apt purge -y nginx nginx-common nginx-core
        sudo apt autoremove -y
        sudo rm -rf /etc/nginx /var/log/nginx /var/www/html
        print_success "Nginx uninstalled successfully!"
    else
        print_info "Nginx uninstallation cancelled."
    fi
}

# Function to uninstall MySQL
uninstall_mysql() {
    if ! is_mysql_installed; then
        print_warning "MySQL is not installed."
        return 0
    fi
    
    print_warning "This will completely remove MySQL and ALL databases!"
    print_error "All your data will be lost. Make sure you have backups!"
    read -p "Are you absolutely sure? (yes/no): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        print_info "Uninstalling MySQL..."
        sudo systemctl stop mysql 2>/dev/null || true
        sudo apt purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-*
        sudo apt autoremove -y
        sudo rm -rf /etc/mysql /var/lib/mysql /var/log/mysql
        print_success "MySQL uninstalled successfully!"
    else
        print_info "MySQL uninstallation cancelled."
    fi
}

# Function to uninstall PHP
uninstall_php() {
    local php_versions=$(get_installed_php_versions)
    
    if [ -z "$php_versions" ]; then
        print_warning "No PHP versions are installed."
        return 0
    fi
    
    echo "Installed PHP versions:"
    local i=1
    local versions_array=()
    for version in $php_versions; do
        echo "$i) PHP $version"
        versions_array+=("$version")
        ((i++))
    done
    echo "$i) Uninstall all PHP versions"
    
    read -p "Select version to uninstall (1-$i): " choice
    
    if [ "$choice" -eq "$i" ]; then
        print_warning "This will remove ALL PHP versions and extensions!"
        read -p "Are you sure? (y/n): " confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Uninstalling all PHP versions..."
            sudo apt purge -y 'php*'
            sudo apt autoremove -y
            sudo rm -rf /etc/php
            print_success "All PHP versions uninstalled successfully!"
        fi
    elif [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        local selected_version="${versions_array[$((choice-1))]}"
        print_info "Uninstalling PHP $selected_version..."
        sudo apt purge -y "php$selected_version*"
        sudo apt autoremove -y
        sudo rm -rf "/etc/php/$selected_version"
        print_success "PHP $selected_version uninstalled successfully!"
    else
        print_error "Invalid choice."
    fi
}

# Function to uninstall Composer
uninstall_composer() {
    if ! is_composer_installed; then
        print_warning "Composer is not installed."
        return 0
    fi
    
    read -p "Are you sure you want to uninstall Composer? (y/n): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Uninstalling Composer..."
        sudo rm -f /usr/local/bin/composer
        print_success "Composer uninstalled successfully!"
    else
        print_info "Composer uninstallation cancelled."
    fi
}

# Function to show uninstall menu
show_uninstall_menu() {
    while true; do
        clear
        echo "======================================"
        echo "   Uninstall Components"
        echo "======================================"
        echo ""
        echo "1) Uninstall Nginx"
        echo "2) Uninstall MySQL"
        echo "3) Uninstall PHP"
        echo "4) Uninstall Composer"
        echo "5) Uninstall Everything"
        echo "6) Back to Main Menu"
        echo ""
        
        read -p "Select an option (1-6): " choice
        
        case $choice in
            1)
                uninstall_nginx
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                uninstall_mysql
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                uninstall_php
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                uninstall_composer
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                print_warning "This will uninstall the entire LEMP stack!"
                print_error "All data will be lost. Make sure you have backups!"
                read -p "Type 'DELETE EVERYTHING' to confirm: " confirm
                
                if [[ "$confirm" == "DELETE EVERYTHING" ]]; then
                    uninstall_nginx
                    echo ""
                    uninstall_mysql
                    echo ""
                    uninstall_php
                    echo ""
                    uninstall_composer
                    echo ""
                    print_success "LEMP stack completely uninstalled!"
                else
                    print_info "Uninstallation cancelled."
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            6)
                break
                ;;
            *)
                print_error "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# Main program loop
main() {
    # Check if running on Ubuntu/Debian
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot determine Linux distribution."
        exit 1
    fi
    
    source /etc/os-release
    if [[ ! "$ID" =~ ^(ubuntu|debian)$ ]]; then
        print_error "This script only supports Ubuntu and Debian-based distributions."
        print_error "Detected: $PRETTY_NAME"
        exit 1
    fi
    
    print_info "Detected: $PRETTY_NAME"
    
    # Check if running as root or with sudo
    if [ "$EUID" -eq 0 ]; then
        print_error "Please do not run this script as root. Use your regular user account."
        print_info "The script will prompt for sudo password when needed."
        exit 1
    fi
    
    # Check if sudo is available
    if ! command_exists sudo; then
        print_error "sudo is not installed. Please install sudo first."
        exit 1
    fi
    
    while true; do
        show_main_menu
        read -p "Select an option (1-4): " choice
        
        case $choice in
            1)
                install_lemp
                ;;
            2)
                show_uninstall_menu
                ;;
            3)
                check_installation_status
                ;;
            4)
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please try again."
                sleep 2
                ;;
        esac
    done
}

# Run main program
main
