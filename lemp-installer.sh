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
    echo "1) Install Full LEMP Stack"
    echo "2) Install Specific Components"
    echo "3) Uninstall Components"
    echo "4) Check Installation Status"
    echo "5) Create Nginx Domain Config"
    echo "6) Setup a Laravel Project"
    echo "7) Exit"
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
    
    print_info "Installing Nginx and Certbot plugin..."
    sudo apt install nginx python3-certbot-nginx -y
    print_success "Nginx and Certbot plugin installed successfully!"
}

# Function to install MySQL
install_mysql() {
    if is_mysql_installed; then
        print_warning "MySQL is already installed. Skipping..."
        return 0
    fi

    print_info "Installing MySQL..."
    sudo apt install mysql-server -y

    echo ""
    print_info "MySQL Configuration"
    read -p "Enter MySQL root username: " MYSQL_ROOT_USER
    read -sp "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
    echo ""

    print_info "Securing MySQL installation..."

    # Detect Ubuntu version
    UBUNTU_VERSION=$(lsb_release -rs)
    UBUNTU_MAJOR=$(echo "$UBUNTU_VERSION" | cut -d'.' -f1)

    if [[ "$UBUNTU_MAJOR" -ge 24 ]]; then
        # Ubuntu 24.04+ — MySQL 8.0+ defaults to caching_sha2_password,
        # must explicitly set mysql_native_password for broad compatibility
        print_info "Detected Ubuntu 24.04+, applying compatible MySQL auth configuration..."

        sudo mysql <<EOF
-- Create new admin user with explicit native password auth
CREATE USER IF NOT EXISTS '${MYSQL_ROOT_USER}'@'localhost'
    IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_ROOT_USER}'@'localhost' WITH GRANT OPTION;

-- Alter root to use native password (keep as system fallback)
ALTER USER 'root'@'localhost'
    IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Disallow remote root login
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\_%';

FLUSH PRIVILEGES;
EOF

    else
        # Ubuntu < 24.04 — original logic works fine
        print_info "Detected Ubuntu ${UBUNTU_VERSION}, applying standard MySQL configuration..."

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
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
-- Reload privilege tables
FLUSH PRIVILEGES;
EOF

    fi

    print_success "MySQL secured successfully!"

    # Verify login works before proceeding
    if ! mysql --user="${MYSQL_ROOT_USER}" --password="${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" &>/dev/null; then
        print_error "Login verification failed! Check your credentials."
        return 1
    fi
    print_success "Login verified successfully."

    # Ask if user wants to create databases
    echo ""
    read -p "Do you want to create databases now? (y/n): " create_dbs
    if [[ "$create_dbs" =~ ^[Yy]$ ]]; then
        read -p "Enter database names (comma-separated, e.g., db1,db2): " MYSQL_DATABASES

        if [ -n "$MYSQL_DATABASES" ]; then
            IFS=',' read -r -a DB_ARRAY <<< "$MYSQL_DATABASES"
            for DB_NAME in "${DB_ARRAY[@]}"; do
                DB_NAME=$(echo "$DB_NAME" | xargs)
                mysql --user="${MYSQL_ROOT_USER}" --password="${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${MYSQL_ROOT_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
                print_success "Database '${DB_NAME}' created and privileges granted."
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

# Function to show installation submenu for individual components
show_install_submenu() {
    while true; do
        clear
        echo "======================================"
        echo "   Install Specific Components"
        echo "======================================"
        echo ""
        echo "1) Install Nginx"
        echo "2) Install MySQL"
        echo "3) Install PHP"
        echo "4) Install Composer"
        echo "5) Back to Main Menu"
        echo ""

        read -p "Select options (e.g., 1,2,4 or 5 to back): " input

        if [[ -z "$input" ]]; then
            print_error "Input cannot be empty."
            sleep 2
            continue
        fi

        # Extract options into an array
        IFS=',' read -ra choices <<< "$input"
        
        # Validation pass
        local valid=true
        local selected_components=()
        local back_selected=false

        for choice in "${choices[@]}"; do
            # Trim whitespace
            choice=$(echo "$choice" | xargs)
            
            if [[ "$choice" =~ ^[1-4]$ ]]; then
                selected_components+=("$choice")
            elif [[ "$choice" == "5" ]]; then
                back_selected=true
            else
                print_error "Invalid option: '$choice'. Valid options are 1, 2, 3, 4, or 5."
                valid=false
            fi
        done

        if [ "$valid" = false ]; then
            sleep 2
            continue
        fi

        # Process selections
        if [ ${#selected_components[@]} -gt 0 ]; then
            print_info "Updating package lists..."
            sudo apt update
            
            for component in "${selected_components[@]}"; do
                case $component in
                    1) install_nginx ;;
                    2) install_mysql ;;
                    3) install_php ;;
                    4) install_composer ;;
                esac
                echo ""
            done
            print_success "Selected components installation process completed."
            read -p "Press Enter to continue..."
        fi

        if [ "$back_selected" = true ]; then
            break
        fi
    done
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

# Function to create Nginx configuration for a domain
create_nginx_config() {
    clear
    echo "======================================"
    echo "   Create Nginx Domain Config"
    echo "======================================"
    echo ""

    if ! is_nginx_installed; then
        print_error "Nginx is not installed. Please install it first."
        read -p "Press Enter to continue..."
        return
    fi

    # Domain Name
    read -p "Enter domain name (e.g., example.com): " DOMAIN_NAME
    if [ -z "$DOMAIN_NAME" ]; then
        print_error "Domain name cannot be empty."
        read -p "Press Enter to continue..."
        return
    fi

    # Root Directory
    DEFAULT_ROOT="/var/www/$DOMAIN_NAME/public"
    read -p "Enter root directory [$DEFAULT_ROOT]: " ROOT_DIR
    ROOT_DIR=${ROOT_DIR:-$DEFAULT_ROOT}

    # PHP Version
    local php_versions=$(get_installed_php_versions)
    if [ -n "$php_versions" ]; then
        echo ""
        echo "Detected PHP versions: $php_versions"
        read -p "Enter PHP version to use (e.g., 8.2): " SELECTED_PHP
        if [ -z "$SELECTED_PHP" ]; then
            SELECTED_PHP=$(echo "$php_versions" | awk '{print $1}')
            print_info "No version entered, using $SELECTED_PHP"
        fi
    else
        read -p "No PHP detected. Enter PHP version manually (e.g., 8.1): " SELECTED_PHP
        if [ -z "$SELECTED_PHP" ]; then
            SELECTED_PHP="8.1"
        fi
    fi

    # Create directory if it doesn't exist
    print_info "Creating directory $ROOT_DIR..."
    sudo mkdir -p "$ROOT_DIR"
    sudo chown -R $USER:$USER "$(dirname "$ROOT_DIR")"

    # Create Nginx Config
    CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN_NAME"
    print_info "Creating Nginx configuration file at $CONFIG_FILE..."

    sudo tee "$CONFIG_FILE" > /dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME;
    root $ROOT_DIR;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php${SELECTED_PHP}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

    # Enable path
    print_info "Enabling configuration..."
    sudo ln -sf "$CONFIG_FILE" "/etc/nginx/sites-enabled/"

    # Test and reload
    if sudo nginx -t; then
        print_info "Reloading Nginx..."
        sudo systemctl reload nginx
        print_success "Nginx configuration created and enabled successfully!"
        echo ""
        print_info "Domain: $DOMAIN_NAME"
        print_info "Root: $ROOT_DIR"
        print_info "PHP: $SELECTED_PHP"
        print_info "Config file: $CONFIG_FILE"
        echo ""
        print_info "You can now run 'sudo certbot --nginx -d $DOMAIN_NAME' to get an SSL certificate."
    else
        print_error "Nginx configuration test failed. Please check the config file."
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Function to setup a Laravel project
setup_laravel_project() {
    clear
    echo "======================================"
    echo "   Setup a Laravel Project"
    echo "======================================"
    echo ""

    read -p "Enter the absolute path where the Laravel project is cloned (e.g., /var/www/myproject): " PROJECT_PATH
    
    if [ ! -d "$PROJECT_PATH" ]; then
        print_error "Directory does not exist: $PROJECT_PATH"
        read -p "Press Enter to continue..."
        return
    fi
    
    cd "$PROJECT_PATH" || return

    # Check if we're in a Laravel project
    if [ ! -f "artisan" ]; then
        print_error "Error: artisan file not found. Are you in a Laravel project directory?"
        read -p "Press Enter to continue..."
        return
    fi

    # Step 0: Install dependencies via Composer
    print_info "Checking for Composer..."
    if ! command -v composer &> /dev/null; then
        print_error "Composer is not installed. Please install Composer and try again."
        read -p "Press Enter to continue..."
        return
    fi

    print_info "Running composer install..."
    if composer install --no-interaction --prefer-dist; then
        print_success "Composer dependencies installed successfully"
    else
        print_error "Composer install encountered errors (possibly in post-install scripts). Carrying on..."
    fi

    echo ""

    # Step 1: Create .env file from .env.example if it doesn't exist
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            print_info "Creating .env file from .env.example..."
            cp .env.example .env
            print_success ".env file created"
        else
            print_error ".env.example file not found!"
            read -p "Press Enter to continue..."
            return
        fi
    else
        print_warning ".env file already exists, skipping creation"
    fi

    echo ""

    # Step 2: Get database credentials interactively
    print_info "Database Configuration"
    echo "========================================"

    read -p "Enter DB_CONNECTION [mysql]: " DB_CONNECTION
    DB_CONNECTION=${DB_CONNECTION:-mysql}

    read -p "Enter DB_HOST [127.0.0.1]: " DB_HOST
    DB_HOST=${DB_HOST:-127.0.0.1}

    read -p "Enter DB_PORT [3306]: " DB_PORT
    DB_PORT=${DB_PORT:-3306}

    read -p "Enter DB_DATABASE [laravel]: " DB_DATABASE
    DB_DATABASE=${DB_DATABASE:-laravel}

    read -p "Enter DB_USERNAME [root]: " DB_USERNAME
    DB_USERNAME=${DB_USERNAME:-root}

    read -sp "Enter DB_PASSWORD (hidden) []: " DB_PASSWORD
    DB_PASSWORD=${DB_PASSWORD:-}

    echo ""
    print_info "The database name you provided will be created automatically if it doesn't exist."
    echo ""
    print_info "Updating .env file with database credentials..."

    # Detect OS for sed compatibility
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        SED_INPLACE="sed -i .bak"
    else
        # Linux
        SED_INPLACE="sed -i"
    fi

    # Update .env file with database credentials
    $SED_INPLACE "s/^DB_CONNECTION=.*/DB_CONNECTION=${DB_CONNECTION}/" .env
    $SED_INPLACE "s/^DB_HOST=.*/DB_HOST=${DB_HOST}/" .env
    $SED_INPLACE "s/^DB_PORT=.*/DB_PORT=${DB_PORT}/" .env
    $SED_INPLACE "s/^DB_DATABASE=.*/DB_DATABASE=${DB_DATABASE}/" .env
    $SED_INPLACE "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USERNAME}/" .env

    # Handle DB_PASSWORD separately as it might contain special characters
    if grep -q "^DB_PASSWORD=" .env; then
        $SED_INPLACE "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|" .env
    else
        echo "DB_PASSWORD=${DB_PASSWORD}" >> .env
    fi

    # Set APP_DEBUG=false
    if grep -q "^APP_DEBUG=" .env; then
        $SED_INPLACE "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env
    else
        echo "APP_DEBUG=false" >> .env
    fi

    # Set APP_ENV=production
    if grep -q "^APP_ENV=" .env; then
        $SED_INPLACE "s|^APP_ENV=.*|APP_ENV=production|" .env
    else
        echo "APP_ENV=production" >> .env
    fi

    # Remove backup file if on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        rm -f .env.bak
    fi

    print_success "Database credentials updated in .env file"
    echo ""

    # Step 2.5: Create database if it doesn't exist
    print_info "Checking if database '$DB_DATABASE' exists..."
    if mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SHOW DATABASES LIKE '$DB_DATABASE';" | grep -q "$DB_DATABASE"; then
        print_success "Database '$DB_DATABASE' already exists"
    else
        print_info "Creating database '$DB_DATABASE'..."
        if mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "CREATE DATABASE $DB_DATABASE CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
            print_success "Database '$DB_DATABASE' created successfully"
        else
            print_error "Failed to create database '$DB_DATABASE'. Please check your MySQL credentials and permissions."
            read -p "Press Enter to continue..."
            return
        fi
    fi
    echo ""

    # Step 3: Generate application key
    print_info "Generating application key..."
    php artisan key:generate --ansi
    print_success "Application key generated"
    echo ""

    # Step 4: Setup directories and permissions
    print_info "Setting up directories and permissions..."
    echo ""

    DIRECTORIES=(
        "storage"
        "storage/app"
        "storage/app/public"
        "storage/framework"
        "storage/framework/cache"
        "storage/framework/sessions"
        "storage/framework/views"
        "storage/logs"
        "bootstrap/cache"
        "public/uploads"
        "resources/views/_cache"
        "_business"
    )

    # Loop through each directory and apply the required actions
    for DIR in "${DIRECTORIES[@]}"; do
        # Create the directory if it doesn't exist
        if [ ! -d "$DIR" ]; then
            echo "Creating directory: $DIR"
            mkdir -p "$DIR"
        fi
        
        # Change the ownership to www-data (check if running as root/sudo)
        if [ "$EUID" -eq 0 ]; then
            echo "Changing ownership of $DIR to www-data"
            chown -R www-data:www-data "$DIR"
        else
            print_warning "Not running as root/sudo, skipping ownership change for $DIR"
        fi
        
        # Change permissions to make it writable
        echo "Setting writable permissions on $DIR"
        chmod -R 775 "$DIR"
    done

    print_success "Directories created and permissions set"
    echo ""

    # Step 5: Ask about migrations
    print_warning "Database Migration Options"
    echo "========================================"
    read -p "Do you want to run migrations? (y/n) [y]: " RUN_MIGRATE
    RUN_MIGRATE=${RUN_MIGRATE:-y}

    if [[ "$RUN_MIGRATE" =~ ^[Yy]$ ]]; then
        echo ""
        print_warning "⚠️  WARNING: Using 'migrate:fresh' will DROP ALL TABLES and reset your database!"
        read -p "Do you want to use 'migrate:fresh' (resets all data)? (y/n) [n]: " USE_FRESH
        USE_FRESH=${USE_FRESH:-n}
        
        echo ""
        if [[ "$USE_FRESH" =~ ^[Yy]$ ]]; then
            print_info "Running migrate:fresh..."
            php artisan migrate:fresh --force
            print_success "Database reset and migrations completed"
        else
            print_info "Running migrate..."
            php artisan migrate --force
            print_success "Migrations completed"
        fi
        
        echo ""
        # Step 6: Ask about seeding
        read -p "Do you want to run database seeders? (y/n) [n]: " RUN_SEED
        RUN_SEED=${RUN_SEED:-n}
        
        if [[ "$RUN_SEED" =~ ^[Yy]$ ]]; then
            echo ""
            print_info "Running database seeders..."
            php artisan db:seed --force
            print_success "Database seeding completed"
        else
            print_info "Skipping database seeding"
        fi
    else
        print_info "Skipping migrations"
    fi

    echo ""

    # Step 7: Ask about nginx configuration
    print_info "Nginx Configuration"
    echo "========================================"
    read -p "Do you want to create an nginx configuration file? (y/n) [n]: " CREATE_NGINX
    CREATE_NGINX=${CREATE_NGINX:-n}

    if [[ "$CREATE_NGINX" =~ ^[Yy]$ ]]; then
        echo ""
        read -p "Enter domain name (e.g., example.com): " DOMAIN_NAME
        
        # Set GODMODE_DOMAIN in .env file
        if [ -n "$DOMAIN_NAME" ]; then
            print_info "Setting GODMODE_DOMAIN=$DOMAIN_NAME in .env file..."
            # Detect OS for sed compatibility
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS
                SED_INPLACE="sed -i .bak"
            else
                # Linux
                SED_INPLACE="sed -i"
            fi
            
            if grep -q "^GODMODE_DOMAIN=" .env; then
                $SED_INPLACE "s|^GODMODE_DOMAIN=.*|GODMODE_DOMAIN=${DOMAIN_NAME}|" .env
            else
                echo "GODMODE_DOMAIN=${DOMAIN_NAME}" >> .env
            fi
            
            # Remove backup file if on macOS
            if [[ "$OSTYPE" == "darwin"* ]]; then
                rm -f .env.bak
            fi
            
            print_success "GODMODE_DOMAIN set to $DOMAIN_NAME"
        fi
        echo ""
        
        if [ -z "$DOMAIN_NAME" ]; then
            print_error "Domain name is required!"
        else
            read -p "Enter project root path [$(pwd)/public]: " PROJECT_ROOT
            PROJECT_ROOT=${PROJECT_ROOT:-$(pwd)}
            
            read -p "Enter PHP version (e.g., 8.2, 8.1, 8.3) [8.2]: " PHP_VERSION
            PHP_VERSION=${PHP_VERSION:-8.2}
            
            NGINX_CONFIG_FILE="${DOMAIN_NAME}.conf"
            
            print_info "Creating nginx configuration file: $NGINX_CONFIG_FILE"
            
            cat > "$NGINX_CONFIG_FILE" << EOF
server {
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME} *.${DOMAIN_NAME};
    root ${PROJECT_ROOT}/public;

    client_max_body_size 128m;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param PHP_VALUE "upload_max_filesize=128M \n post_max_size=128M";
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    listen 80;
    # Uncomment the lines below after setting up SSL with Certbot
    # listen 443 ssl;
    # ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;
    # include /etc/letsencrypt/options-ssl-nginx.conf;
    # ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}
EOF
            
            print_success "Nginx configuration file created: $NGINX_CONFIG_FILE"
            echo ""
            
            # Ask if user wants to deploy the nginx config automatically
            read -p "Do you want to deploy this nginx configuration now? (requires sudo) (y/n) [y]: " DEPLOY_NGINX
            DEPLOY_NGINX=${DEPLOY_NGINX:-y}
            
            if [[ "$DEPLOY_NGINX" =~ ^[Yy]$ ]]; then
                echo ""
                print_info "Deploying nginx configuration..."
                
                # Check if nginx is installed
                if ! command -v nginx &> /dev/null; then
                    print_error "Nginx is not installed. Please install nginx first."
                else
                    # Copy config to sites-available
                    print_info "Copying config to /etc/nginx/sites-available/..."
                    if sudo cp "$NGINX_CONFIG_FILE" /etc/nginx/sites-available/; then
                        print_success "Config copied to sites-available"
                    else
                        print_error "Failed to copy config. Do you have sudo privileges?"
                        read -p "Press Enter to continue..."
                        return
                    fi
                    
                    # Create symlink to sites-enabled
                    print_info "Creating symlink in sites-enabled..."
                    if [ -L "/etc/nginx/sites-enabled/$NGINX_CONFIG_FILE" ]; then
                        print_warning "Symlink already exists, removing old one..."
                        sudo rm "/etc/nginx/sites-enabled/$NGINX_CONFIG_FILE"
                    fi
                    
                    if sudo ln -s "/etc/nginx/sites-available/$NGINX_CONFIG_FILE" /etc/nginx/sites-enabled/; then
                        print_success "Symlink created in sites-enabled"
                    else
                        print_error "Failed to create symlink"
                        read -p "Press Enter to continue..."
                        return
                    fi
                    
                    # Test nginx configuration
                    print_info "Testing nginx configuration..."
                    if sudo nginx -t; then
                        print_success "Nginx configuration test passed"
                        
                        # Reload nginx
                        print_info "Reloading nginx..."
                        if sudo systemctl reload nginx; then
                            print_success "Nginx reloaded successfully"
                            echo ""
                            print_success "Nginx configuration deployed and active!"
                        else
                            print_error "Failed to reload nginx"
                            read -p "Press Enter to continue..."
                            return
                        fi
                    else
                        print_error "Nginx configuration test failed. Please check the configuration."
                        read -p "Press Enter to continue..."
                        return
                    fi
                fi
                
                echo ""
                print_info "Optional: Setup SSL with Certbot:"
                echo "  sudo certbot --nginx -d ${DOMAIN_NAME} -d www.${DOMAIN_NAME}"
                echo ""
            else
                print_info "Nginx configuration saved as: $NGINX_CONFIG_FILE"
                echo ""
                print_info "To deploy manually later, run:"
                echo "  sudo cp $NGINX_CONFIG_FILE /etc/nginx/sites-available/"
                echo "  sudo ln -s /etc/nginx/sites-available/$NGINX_CONFIG_FILE /etc/nginx/sites-enabled/"
                echo "  sudo nginx -t"
                echo "  sudo systemctl reload nginx"
                echo ""
            fi

            # Step 7.5: SSL Configuration
            print_info "SSL Configuration"
            echo "========================================"
            read -p "Do you want to configure SSL with Certbot now? (y/n) [n]: " CONFIG_SSL
            CONFIG_SSL=${CONFIG_SSL:-n}

            if [[ "$CONFIG_SSL" =~ ^[Yy]$ ]]; then
                echo ""
                # Verify if Nginx config exists in /etc/nginx before proceeding
                NGINX_PATH="/etc/nginx/sites-available/${DOMAIN_NAME}.conf"
                
                if [ ! -f "$NGINX_PATH" ]; then
                    print_error "Nginx configuration for $DOMAIN_NAME not found in /etc/nginx/sites-available/."
                    print_error "Please deploy the Nginx configuration first (run Step 7 with 'y' for deployment)."
                else
                    print_info "Checking for Certbot..."
                    if ! command -v certbot &> /dev/null; then
                        print_info "Certbot not found. Installing Certbot and Nginx plugin..."
                        if [ "$EUID" -eq 0 ]; then
                            apt update && apt install -y certbot python3-certbot-nginx
                        else
                            sudo apt update && sudo apt install -y certbot python3-certbot-nginx
                        fi
                        print_success "Certbot installed successfully"
                    else
                        print_success "Certbot is already installed"
                    fi

                    echo ""
                    echo "Select SSL Certificate type:"
                    echo "1) Standard (domain.com, www.domain.com)"
                    echo "2) Wildcard (*.domain.com) - Requires manual DNS TXT record"
                    read -p "Enter choice [1]: " SSL_TYPE
                    SSL_TYPE=${SSL_TYPE:-1}

                    if [ "$SSL_TYPE" == "1" ]; then
                        print_info "Fetching Standard SSL certificate..."
                        
                        # Ask to include www subdomain
                        CERTBOT_DOMAINS="-d ${DOMAIN_NAME}"
                        if [[ ! "${DOMAIN_NAME}" =~ ^www\. ]]; then
                            read -p "Also include 'www.${DOMAIN_NAME}' subdomain? (y/n) [y]: " INCLUDE_WWW
                            INCLUDE_WWW=${INCLUDE_WWW:-y}
                            if [[ "$INCLUDE_WWW" =~ ^[Yy]$ ]]; then
                                CERTBOT_DOMAINS="${CERTBOT_DOMAINS} -d www.${DOMAIN_NAME}"
                            fi
                        fi
                        
                        if sudo certbot --nginx ${CERTBOT_DOMAINS}; then
                            print_success "SSL certificate installed successfully"
                        else
                            echo ""
                            print_error "Failed to install SSL certificate."
                            print_warning "Possible reasons:"
                            print_warning "1. Domain DNS does not yet point to this server's IP."
                            print_warning "2. Subdomain 'www' not defined in DNS (try again without www)."
                            print_warning "3. Ports 80 or 443 are blocked by a firewall."
                            echo ""
                        fi
                    elif [ "$SSL_TYPE" == "2" ]; then
                        print_info "Fetching Wildcard SSL certificate (DNS manual challenge)..."
                        print_warning "Follow the instructions below to add TXT records to your DNS provider."
                        
                        if sudo certbot certonly --manual --preferred-challenges dns -d "${DOMAIN_NAME}" -d "*.${DOMAIN_NAME}"; then
                            print_success "Wildcard SSL certificate fetched successfully"
                            
                            # Uncomment SSL lines in Nginx config
                            print_info "Updating Nginx configuration to enable SSL..."
                            
                            # Detect OS for sed compatibility
                            if [[ "$OSTYPE" == "darwin"* ]]; then
                                # macOS (for local testing script, though this usually runs on Linux)
                                SED_SSL="sed -i .bak"
                            else
                                # Linux
                                SED_SSL="sed -i"
                            fi
                            
                            sudo $SED_SSL 's/# listen 443 ssl;/listen 443 ssl;/' "$NGINX_PATH"
                            sudo $SED_SSL 's|# ssl_certificate /etc/letsencrypt/|ssl_certificate /etc/letsencrypt/|' "$NGINX_PATH"
                            sudo $SED_SSL 's|# ssl_certificate_key /etc/letsencrypt/|ssl_certificate_key /etc/letsencrypt/|' "$NGINX_PATH"
                            sudo $SED_SSL 's|# include /etc/letsencrypt/options-ssl-nginx.conf;|include /etc/letsencrypt/options-ssl-nginx.conf;|' "$NGINX_PATH"
                            sudo $SED_SSL 's|# ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;|ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;|' "$NGINX_PATH"
                            
                            # Remove backup file if on macOS
                            if [[ "$OSTYPE" == "darwin"* ]]; then
                                sudo rm -f "${NGINX_PATH}.bak"
                            fi
                            
                            print_info "Testing and reloading Nginx..."
                            if sudo nginx -t && sudo systemctl reload nginx; then
                                print_success "SSL enabled and Nginx reloaded"
                            else
                                print_error "Failed to reload Nginx. Please check $NGINX_PATH manually."
                            fi
                        else
                            print_error "Failed to fetch Wildcard SSL certificate"
                        fi
                    else
                        print_error "Invalid choice. Skipping SSL configuration."
                    fi
                fi
            fi
        fi
    else
        print_info "Skipping nginx configuration"
    fi

    echo ""
    echo "========================================"
    print_success "Laravel setup completed successfully!"
    echo "========================================"
    echo ""
    print_info "General next steps:"
    echo "  • Start your development server: php artisan serve"
    echo "  • Review your .env file for any additional configuration"
    if [[ ! "$CREATE_NGINX" =~ ^[Yy]$ ]]; then
        echo "  • Configure your web server to point to the 'public' directory"
    fi
    echo ""
    read -p "Press Enter to return to main menu..."
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
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_warning "============================================"
        print_warning "  WARNING: Running as root user!"
        print_warning "============================================"
        echo ""
        print_warning "You are about to run this script as root."
        print_warning "This is potentially dangerous and should only be done if you know what you're doing."
        echo ""
        print_warning "Running as root will:"
        print_warning "  - Skip sudo password prompts"
        print_warning "  - Execute all commands with full system privileges"
        print_warning "  - Allow direct modification of system files"
        print_warning "  - Bypass user-level permission checks"
        echo ""
        print_warning "If you're not absolutely certain, press Ctrl+C now to cancel."
        echo ""
        read -p "Type 'y' to continue: " confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Cancelled."
            exit 0
        fi
        echo ""
    fi
    
    # Check if sudo is available
    if ! command_exists sudo; then
        print_error "sudo is not installed. Please install sudo first."
        exit 1
    fi
    
    while true; do
        show_main_menu
        read -p "Select an option (1-7): " choice
        
        case $choice in
            1)
                install_lemp
                ;;
            2)
                show_install_submenu
                ;;
            3)
                show_uninstall_menu
                ;;
            4)
                check_installation_status
                ;;
            5)
                create_nginx_config
                ;;
            6)
                setup_laravel_project
                ;;
            7)
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
