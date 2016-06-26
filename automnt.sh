#!/bin/bash

# automnt v.1.0
#
#             Script is inspired by and based on autonfs.sh by Jeroen Hoek
#             https://github.com/jdhoek/util/blob/master/autonfs.sh
#             In contrary to the above mentioned, this script also allows
#             mounting/ unmounting of any other mount type (e.g. cifs).
#
#             See also:
#             http://ubuntuforums.org/showthread.php?t=1389291
#             https://help.ubuntu.com/community/AutomaticallyMountNFSSharesWithoutAutofsHowto
#
# 2016-06-26  Initial release.


# Configuration parameters.

# Check every X seconds (60 is a good default).
INTERVAL=60

# Timeout for pinging CIFS servers.
TIMEOUT=2

# The shares that need to be mounted. The command will be passed to mount as is,
# so write the mount type first, followed by the file system, the mount point
# and the mount options. It's recommended to group entries from the same server,
# because then the server status has to be checked only once.
# Example:
# "-t <TYPE> <DEVICE> <DIR> -o <OPTIONS>"
# where '-o <OPTIONS>' is optional.
MOUNTS=(
	"-t nfs server1:/volume1 /mnt/vol1 -o hard,rsize=8192,wsize=8192,proto=tcp"
	"-t nfs server1:/volume2 /mnt/vol2 -o hard,rsize=8192,wsize=8192,proto=tcp,ro"
	"-t cifs //server2/data  /mnt/data -o hard,credentials=/path/to/credentials,rsize=8192,wsize=8192"
)

# Logging. Set to true for debugging and testing; false when everything works. Logs 
# are written to /var/log/upstart/autonfs.log.
LOG=true

# End of configuration


function log {
    if $LOG; then
        echo $1
    fi
}


log "Automatic mount script started."

while true; do
	# Set a dummy value for each new run.
	LAST_SERVER=""

	# Iterate over each line/mount. The whole line is available in MOUNT now.
	for MOUNT in "${MOUNTS[@]}"; do
		# Divide the line/mount into its single elements.
		ELEMS=(${MOUNT// / })
		# Get the server address (third element).
		SERVER=(${ELEMS[2]})
		# Remove slashes (/).
		SERVER=(${SERVER//\// })
		# Remove colon (:).
		SERVER=(${SERVER//:/ })
		if [ "$SERVER" != "$LAST_SERVER" ]; then
			# Get the mount type (second element).
			TYPE=(${ELEMS[1]})
			# Check cifs server.
			if [ $TYPE == "cifs" ]; then
				# Check status.
				ping "$SERVER" -c 1 -w $TIMEOUT >/dev/null
			# Check nfs server.
			elif [ $TYPE == "nfs" ]; then
				# Check status.
				rpcinfo -t "$SERVER" nfs &>/dev/null
			# Other mount types.
			else
				log "Mount type '$TYPE' is not supported."
				break
			fi
			# Store status.
			STATE=$?
		fi
		if [ $STATE -eq 0 ]; then
			# Server is online.
			log "Server '${SERVER}' is up."
			if grep -qsE "^([^ ])+ ${ELEMS[3]}" /proc/mounts; then
				log "'${ELEMS[3]}' is already mounted."
			else
				# Mount not mounted, attempt mount.
				log "Share not mounted; attempting to mount '${ELEMS[3]}'."
				mount ${MOUNT}
			fi
		else
			# Server is offline.
			log "Server '${SERVER}' is down."
			if grep -qsE "^([^ ])+ ${ELEMS[3]}" /proc/mounts; then
				# Mount is still mounted; attempt umount.
				log "Cannot reach '${SERVER}', unmounting share '${ELEMS[3]}'."
				umount -l ${ELEMS[3]}
			fi
		fi
		# Remember server address for the next line/mount.
		LAST_SERVER=$SERVER
	done
	sleep $INTERVAL
done
