# User Setup Guide


## Overview
This automation sets up multiple developer accounts with proper permissions, team isolation, and logging.


## Features
- Bulk user creation from CSV
- Automatic group (team) management
- Secure home directory permissions
- Structured project directories
- Custom colored shell prompt
- Centralized logging


## Directory Structure
/projects
├── backend
│ ├── alice
│ ├── bob
│ └── shared
├── frontend
│ ├── charlie
│ ├── diana
│ └── shared
└── devops
├── eric
└── shared



## Permissions
| Location | Permission |
|--------|------------|
| Home directories | 700 |
| User project dirs | 755 |
| Team shared dirs | 775 |


## Usage


### Create Users
```bash
sudo ./user_onboarding.sh --create
```

### Cleanup Users
```bash
sudo ./user_onboarding.sh --cleanup
```

### Logs

#### All actions are logged to:
```bash
/var/log/user_management.log
```

### Notes

- Script must be run as root

- CSV file must be in the same directory as the script

- Passwords can be set manually or via chpasswd