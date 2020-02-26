echo "Updating Postfix configuration"
#postmap /etc/postfix/relocated
#postmap /etc/postfix/transport
#postmap hash:/etc/postfix/sasl_passwd
#postmap hash:/etc/postfix/helo_checks
#postmap hash:/etc/postfix/sender_checks
#postmap hash:/etc/postfix/client_checks
newaliases
postfix reload
