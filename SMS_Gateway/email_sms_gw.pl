#!/bin/bash
DIR="/root/bin/smsgateway"
MAILCONF="fetchmailconfig_sms"
echo $msg from $tel on $dat at $tim
MAILBOX="/var/mail/root"
MAILSTORE="/root/mail"

OUTBOX="/root/bin/smsgateway/spool/outbox/"
mkdir -p ${OUTBOX}
mydate=`date | tr -s ' ' | tr ' ' '_'`
fetchmail  --fetchmailrc ${DIR}/${MAILCONF}  --mda maildrop
cat ${MAILBOX} | formail -ds sh -c 'cat > ${MAILSTORE}/msg.$FILENO';
rm ${MAILBOX}


for f in `ls ${MAILSTORE}/msg.*`; do
echo $f
tel=`cat ${f} | grep To | cut -d : -f 2 | cut -d @ -f 1 | sed 's/ //g' | sed 's/<//g' | sed 's/>//g'  | cut -d " " -f 1 | head -1 ` 
echo "TEL: $tel"
head=`cat ${f} | grep Subject |  grep -v "MIME-Version" | cut -d : -f 2 | sed 's/ //'`
echo "HEAD: $head"
msg=`cat ${f} | grep "Content-Transfer" -A 20 | grep -v "Content-Transfer"  | grep -v "X-MS" | grep -v "MIME" | grep -v "X-Orig" | grep -v "UTC" |sed '/^$/d' | head -3`
echo "MSG: $msg"
echo "End MSG"

logger -i Sending message to $tel
echo "${head}:${msg}" > ${OUTBOX}/${tel}_${mydate}
rm ${f}
done



