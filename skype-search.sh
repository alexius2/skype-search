#!/bin/bash

usage="usage: $(basename "$0") [-A num] [-B num] [-c count] expression

Search specified expression in main.db database

-A num
    Print num lines of trailing context after each match
-B num
    Print num lines of leading context before each match
-c count
    Limit number of result lines
-d dialog
    Search messages only inside given chat name
--after date
    Search messages sent after given date (format YYYY-MM-DD)
--before date
    Search messages sent before given date (format YYYY-MM-DD)"

OPTIND=1 # Reset in case getopts has been used previously in the shell.


while getopts "A:B:c:d:-:" opt; do
    case $opt in
        A)
            after_context=$OPTARG+1
            ;;
        B)
            before_context=$OPTARG+1
            ;;
        c)
            limit=$OPTARG
            ;;
        d)
            dialog=$OPTARG
            ;;
        -)
            case "${OPTARG}" in
                after)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    if [[ ! $val =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                        echo "Uknown format for date: $val" >&2
                        exit 1
                    fi

                    after_datetime=${val}
                    ;;
                before)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    if [[ ! $val =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                        echo "Uknown format for date: $val" >&2
                        exit 1
                    fi

                    before_datetime=${val}
                    ;;
                *)
                    if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                        echo "Unknown option --${OPTARG}" >&2
                    fi
                    exit 1
                    ;;
            esac;;
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

if [ -z "$@" ]; then
    echo "$usage"
    exit 0
fi

query_part="(select displayname from conversations where id = m2.convo_id) || ' | [' || strftime('%Y-%m-%d, %H:%M:%S', datetime(timestamp, 'unixepoch', 'localtime')) || '] ' || from_dispname || ': ' || body_xml as q"

if [ -n "$dialog" ]; then
    dialog_part=" and convo_id in (select id from conversations where displayname like '%$dialog%')"
fi

where_part=""

if [ -n "$after_datetime" ]; then
    where_part="and timestamp >= strftime('%s', '$after_datetime') + strftime('%s', 'now') - strftime('%s', 'now', 'localtime')"
fi

if [ -n "$before_datetime" ]; then
    where_part="$where_part and timestamp < strftime('%s', '$before_datetime') + strftime('%s', 'now') - strftime('%s', 'now', 'localtime')"
fi


if [ -n "$after_context" ] && [ -n "$before_context" ]; then
    echo "not supported yet"
    exit 1
elif [ -n "$after_context" ]; then
    query="select (select group_concat((select m3.q), x'0a') from (select $query_part from messages m2 where m2.convo_id = m.convo_id and m2.id >= m.id order by m2.timestamp limit $after_context) m3 ) || x'0a' || '--' from messages m where m.body_xml like '%$@%' $dialog_part $where_part order by timestamp"
elif [ -n "$before_context" ]; then
    query="select (select group_concat((select m4.q), x'0a') from (select q from (select $query_part, timestamp from messages m2 where m2.convo_id = m.convo_id and m2.id <= m.id order by m2.timestamp desc limit $before_context) m3 order by timestamp asc) m4 ) || x'0a' || '--' from messages m where m.body_xml like '%$@%' $dialog_part $where_part order by timestamp"
else
    query="select $query_part from messages m2 where body_xml like '%$@%' $dialog_part $where_part order by timestamp"
fi

if [ -n "$limit" ]; then
    query="$query limit $limit;"
else
    query="$query;"
fi

echo $query | sqlite3 $filename | sed -f unescape-html.sh | less
