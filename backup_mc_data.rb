#!/usr/bin/env ruby
require 'net/http'

BACKUP_DESTINATION_DIR = '/home/nanodano/mc_backup_rotate/backup_test'
DISCORD_WEBHOOK_URL = ''
DIR_TO_BACKUP = '/home/nanodano'
DB_USER = 'username'
DB_HOST = '127.0.0.1'
DB_NAME = 'dbname'
DB_PASS = 'password'
BACKUP_COUNT_LIMIT = 3
REMOTE_SSH_HOST = '8.8.8.8'
REMOTE_SSH_USER = 'user'


$formatted_date = Time::now.strftime("%Y%m%d-%H%M%S")
$mysql_output_filename = 'mc-mysql-' + $formatted_date + '.mysql'
$server_backup_filename = 'mc-server-' + $formatted_date + '.tar'


def error_exit(msg)
  full_message = "[-] Error during backup: " + msg
  puts full_message
  post_discord_webhook full_message
  exit(1)
end


def post_discord_webhook(msg)
  puts '[*] Posting message to discord: ' + msg
  uri = URI(DISCORD_WEBHOOK_URL)
  Net::HTTP.post_form(uri, 'content' => msg)
end


def archive_directory(dir_to_backup)
  puts '[*] Attempting to backup: ' + dir_to_backup + ' to ' + $server_backup_filename
  `tar cf #{$server_backup_filename} #{dir_to_backup} 2>/dev/null`
  if $?.exitstatus != 0
    error_exit "[-] Tar failed to create file."
  end
  `rm #{$server_backup_filename}.gz 2>/dev/null` # prevent 'do you want to overwrite' message
  `gzip #{$server_backup_filename}`
  if $?.exitstatus != 0
    error_exit "[-] Gzip failed on server backup."
  end
end


def archive_database(user, pass, name, host)
  `mysqldump -u#{user} -p#{pass} -h#{host} #{name} > #{$mysql_output_filename} 2>/dev/null`
  if $?.exitstatus != 0
    error_exit 'Mysqldump failed.'
  end
  `rm #{$mysql_output_filename}.gz 2>/dev/null`
  `gzip #{$mysql_output_filename}`
  if $?.exitstatus != 0
    error_exit 'Gzip failed on db.'
  end
end


def rotate_backups(pattern)
  files = Dir::glob(pattern)
  if files.length <= BACKUP_COUNT_LIMIT
    return
  end
  files.sort!
  puts files[0]
  File::delete(files[0])
end


def sync_with_remote
  puts "[*] Syncing backups with remote server #{REMOTE_SSH_HOST}"
  `rsync ./ #{REMOTE_SSH_USER}@#{REMOTE_SSH_HOST}:backups/ --delete --recursive`
  if $?.exitstatus != 0
    error_exit '[-] Failed to sync backups remotely.'
  end
  puts "[*] Done syncing backups with #{REMOTE_SSH_HOST}."
end


def main
  puts "[*] Ruby backup script starting..."
  begin
    Dir::chdir(BACKUP_DESTINATION_DIR)
  rescue
    error_exit "[-] Directory does not exist" + BACKUP_DESTINATION_DIR
  end
  archive_directory DIR_TO_BACKUP
  archive_database DB_USER, DB_PASS, DB_NAME, DB_HOST
  rotate_backups '*.tar.gz'
  rotate_backups '*.mysql.gz'
  sync_with_remote
  puts "[+] Ruby backup script completed successfully!"
end


main
