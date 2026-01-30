#!/bin/bash
# user_onboarding.sh
# Modes: --create | --cleanup


CSV_FILE="users.csv"
LOG_FILE="/var/log/user_management.log"


log() {
echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" | tee -a "$LOG_FILE"
}


create_users() {
while IFS=',' read -r username team; do
# Skip header
[[ "$username" == "username" ]] && continue


# Create group if not exists
if ! getent group "$team" > /dev/null; then
groupadd "$team"
log "Group created: $team"
fi


# Create user
if ! id "$username" &>/dev/null; then
useradd -m -g "$team" "$username"
log "User created: $username (team: $team)"
fi


# Permissions for home directory
chmod 700 "/home/$username"


# Create project directories
mkdir -p "/projects/$team/$username"
chmod 755 "/projects/$team/$username"
chown -R "$username:$team" "/projects/$team/$username"


# Shared directory per team
mkdir -p "/projects/$team/shared"
chmod 775 "/projects/$team/shared"
chown -R ":$team" "/projects/$team/shared"


# Custom bash prompt
cat <<EOF >> /home/$username/.bashrc
# Custom colored prompt
export PS1='\[\e[32m\]\u@\h \[\e[34m\]\w \[\e[0m\]$ '
EOF


chown "$username:$team" "/home/$username/.bashrc"
log "Environment configured for $username"


done < "$CSV_FILE"
}


cleanup_users() {
while IFS=',' read -r username team; do
[[ "$username" == "username" ]] && continue


userdel -r "$username" &>/dev/null && log "User removed: $username"
done < "$CSV_FILE"


rm -rf /projects
log "Project directories removed"
}


case "$1" in
--create)
create_users
;;
--cleanup)
cleanup_users
;;
*)
echo "Usage: $0 --create | --cleanup"
exit 1
;;
esac
