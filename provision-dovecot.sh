#!/bin/bash
set -eux

config_domain=$(hostname --domain)

apt-get install -y --no-install-recommends dovecot-imapd dovecot-sqlite sqlite3

# stop dovecot before we configure it.
systemctl stop dovecot

# configure it.
cat >/etc/dovecot/dovecot.conf <<EOF
listen = 0.0.0.0
protocols = imap
ssl = required
ssl_key = </etc/ssl/private/$config_domain-key.pem
ssl_cert = </etc/ssl/certs/$config_domain-crt.pem
auth_mechanisms = plain login
disable_plaintext_auth = no
first_valid_gid = 1000
first_valid_uid = 1000
mail_location = maildir:/var/vmail/%d/%n

passdb {
  args = /etc/dovecot/dovecot-sql.conf
  driver = sql
}

userdb {
  args = /etc/dovecot/dovecot-sql.conf
  driver = sql
}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    user = postfix
    group = postfix
    mode = 0660
  }

  unix_listener auth-master {
    user = vmail
    group = vmail
    mode = 0600
  }
}

protocol lda {
  postmaster_address = postmaster@$config_domain
}
EOF

# setup the users database.
cat >/etc/dovecot/dovecot-sql.conf <<EOF 
driver = sqlite
connect = /etc/dovecot/users.sqlite
default_pass_scheme = PLAIN-MD5
password_query = SELECT password FROM users WHERE email = '%u' AND enabled = 1
#user_query = SELECT '/var/vmail/%d/%n' as home, `id -u vmail` as uid, `id -g vmail` as gid, 'maildir:storage=' || quota as quota FROM users WHERE email = '%u'
user_query = SELECT '/var/vmail/%d/%n' as home, `id -u vmail` as uid, `id -g vmail` as gid FROM users WHERE email = '%u'
EOF
cat <<EOF | sqlite3 /etc/dovecot/users.sqlite
CREATE TABLE users (
  email VARCHAR(128) PRIMARY KEY,
  password VARCHAR(64) NOT NULL,
  enabled INTEGER(1) DEFAULT 1 NOT NULL
  -- quota is in KiBytes
  --quota INTEGER DEFAULT 25000 NOT NULL
);
EOF
chgrp dovecot /etc/dovecot/users.sqlite
chmod 640 /etc/dovecot/users.sqlite

# add the mailboxes from the /etc/postfix/virtual_mailbox_maps file as users.
# NB all passwords are "password".
while read -r line; do
  email=$(echo $line | awk '{print $1}')
  if [[ -z "$email" ]] || [[ "$email" = \#* ]]; then
    continue
  fi
  echo "insert into users(email, password)
        values ('$email', '{PLAIN-MD5}5f4dcc3b5aa765d61d8327deb882cf99');" \
    | sqlite3 /etc/dovecot/users.sqlite
done </etc/postfix/virtual_mailbox_maps
sqlite3 /etc/dovecot/users.sqlite vacuum

# all done. start dovecot.
systemctl start dovecot

# configure postfix to use the dovecot userdb.
postconf -e 'smtpd_sasl_auth_enable = yes'
postconf -e 'smtpd_sasl_type = dovecot'
postconf -e 'smtpd_sasl_path = private/auth'
systemctl restart postfix

# send test email.
sendmail root <<EOF
Subject: Hello World from `hostname --fqdn` at `date --iso-8601=seconds`

Hello World! 
EOF
