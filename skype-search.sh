#!/bin/bash

OPTIND=1 # Reset in case getopts has been used previously in the shell.


while getopts "A:B:C:" opt; do
  case $opt in
    A)
	  after_context=$OPTARG+1
      ;;
    B)
      before_context=$OPTARG+1
      ;;
    C)
      limit=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))
[ "$1" = "--" ] && shift

filename="main.db"

if [ ! -r $filename ]; then
    echo "Database file $filename is not readable or not exists" >&2
    exit 1
fi

query_part="(select displayname from conversations where id = m2.convo_id) || ' | [' || strftime('%Y-%m-%d, %H:%M:%S', datetime(timestamp, 'unixepoch', 'localtime')) || '] ' || from_dispname || ': ' || body_xml as q"

if [ -n "$after_context" ] && [ -n "$before_context" ]; then
	echo "not supported yet"
	exit 1
elif [ -n "$after_context" ]; then
	query="select (select group_concat((select m3.q), x'0a') from (select $query_part from messages m2 where m2.convo_id = m.convo_id and m2.id >= m.id order by m2.timestamp limit $after_context) m3 ) || x'0a' || '--' from messages m where m.body_xml like '%$@%' order by timestamp"
elif [ -n "$before_context" ]; then
	query="select (select group_concat((select m4.q), x'0a') from (select q from (select $query_part, timestamp from messages m2 where m2.convo_id = m.convo_id and m2.id <= m.id order by m2.timestamp desc limit $before_context) m3 order by timestamp asc) m4 ) || x'0a' || '--' from messages m where m.body_xml like '%$@%' order by timestamp"
else
	query="select $query_part from messages m2 where body_xml like '%$@%' order by timestamp"
fi

if [ -n "$limit" ]; then
    query="$query limit $limit;"
else
	query="$query;"
fi

echo $query | sqlite3 $filename | sed -f unescape-html.sh | less