#!/bin/bash
##########################################
#
# NFS installation & configuration script
#
##########################################
#
# By Johan CHASSAING
# On 2014-01-26
# Last modification 2014-02-07
#
##########################################

##########################################
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>. 
#
##########################################


##########################################
#
#               Variables
#
##########################################

DATE=`date +%d-%m-%Y`
TIME=`date +%H:%M`
LOG=$(dirname $0)/log.txt
SCRIPTNAME=$(basename $0)
EXPORTS="/etc/exports"
DENY="/etc/hosts.deny"
ALLOW="/etc/hosts.allow"

DOIT=0 
DOITIP=0
opt_usage=0
opt_install=0
opt_uninstall=0
opt_addShare=0
opt_removeShare=0

##########################################
#
# 		Functions
#
##########################################

##########################################
#         Last function before exit

# Show log path before exit
finish()
{
  # Show log path
  echoInfo "Log file created at $LOG"
  sleep 1
}

##########################################
# 		Echo colorization 

# Insert color for ok/info/error

echoOk()
{
  echo -e "\e[0;32m [OK]\e[0m $1 " | tee -a $LOG
}

echoInfo()
{ 
  echo -e "\e[0;33m [Info]\e[0m $1 " | tee -a $LOG
}

echoError()
{
  echo -e "\e[0;31m [Error]\e[0m $1 " | tee -a $LOG
}

##########################################
#               Bad Parameters

# show error message and usage then exit
bad_Parameters()
{
  echoError "Bad parameters, please check"
  usage
}



##########################################
# 		Usage

# How to use this script
usage()
{
  echo "  $SCRIPTNAME usage:"
  echo "  -h show help"
  echo "  -i install NFS server"
  echo "  -u uninstall NFS server"
  echo "  Add a share"
  echo "    -a -s <share name> -c <client IP>"
  echo "  Remove a share"
  echo "    -r -s <share name> -c <client IP>"
  echo "    -r -s <share name>"
  exit 1
}


##########################################
# 		checkRoot

# Check the user if root

checkRoot()
{
  if [[ "$(id -u)" -ne 0 ]]; then 
    echoError "You must be root"
    exit 1
  fi
  echoOk "Launched by root"
}


##########################################
# 		checkPackageNfs

# Check if the package is installed

checkPackageNfs()
{
  if [[ $(dpkg -l nfs-kernel-server 2>/dev/null | egrep "^ii " | wc -l) -ne 0 ]]; then 
    return 1
  fi
  return 0
}

##########################################
#               checkValidIp

# Check if an IP is well formated

checkIp()
{
 # return 1 for a good one, else 0
 return  $(echo $1 | egrep "^([0-9]{1,3}\.){3}[0-9]{1,3}$" | wc -l)
}


##########################################
#               checkShare

# Check if the share exists

checkShare()
{
 # return the file line or 0
 if [[  $( grep "$1 " $EXPORTS | wc -l) -eq 0 ]]; then
   echo 0
 else 
   echo $(grep "$1 " $EXPORTS)
 fi
}

##########################################
#               checkShareClient

# Check if the share exist with the specified IP

checkShareClient()
{
 # return 1 if it exists, else 0
 if [[  $( echo $1 | grep $2 | wc -l) -eq 1 ]]; then
   return 1
 else
   return 0
 fi
}

##########################################
#               checkIpInWhitelist

# Check if this IP is in the white list

checkIpInWhitelist()
{
 # return the file line or 0
 if [[  $( grep $1 $ALLOW | wc -l) -eq 0 ]]; then
   return 0
 else
   return 1
 fi
}

##########################################
# 		updatePackagesList

# update 

updatePackagesList()
{
  echo "Updating packages list..."
  `apt-get update &>>$LOG`
  if [[ $? -eq 0 ]]; then
    echoOk "Packages list successfuly upgraded"
  else
    echoError "packages list update failed"
  fi 
}

##########################################
# 		installPackageNfs

# Install NFS

installPackageNfs()
{
  echo "Installing nfs..."  
  #check if nfs is present, if it is not, install it
  checkPackageNfs
  [[ $? -eq 1 ]] && echoError "NFS is already installed"  && exit 1
  `apt-get install nfs-kernel-server -y &>>$LOG`

  if [[ $? -eq 0 ]]; then 
    echoOk "Nfs package has been successfuly installed"
  else
    echoError "Nfs package installation failed"
    exit 1
  fi
  
  # configure security rules 
  # block all connections
  cat <<EOF > $DENY
  portmap:ALL
  lockd:ALL
  mountd:ALL
  rquotad:ALL
  statd:ALL
EOF
  # Allow entries
  cat <<EOF > $ALLOW
  portmap:
  lockd:
  mountd:
  rquotad:
  statd:
EOF
  
  # restart service
  service rpcbind restart &>/dev/null
  if [[ $? -eq 0 ]]; then
    echoOk "Service rpcbind restarted"
  else
    echoError "Service rpcbind restart failed"
  fi
}

##########################################
#               uninstallPackageNfs

# Uninstall NFS 

uninstallPackageNfs()
{
  
  echo "Uninstalling nfs..."
  # check if nfs is not present, if it is, uninstall
  checkPackageNfs
  [[ $? -eq 0 ]] && echoError "NFS is not present" && exit 1
  `apt-get purge nfs-kernel-server nfs-common rpcbind -y &>>$LOG`

  if [[ $? -eq 0 ]]; then
    echoOk "Nfs package has been successfuly removed"
  else
    echoError "Nfs package removal failed"
    exit 1
  fi

}

##########################################
#              		addShare

# Add a share

addShare()
{
  # check if the share already exist or add it
  result=$(checkShare $shareName)
  if [[ "$result" == "0" ]]; then
    echo "$shareName $clientIp(rw,sync,no_subtree_check)" >> $EXPORTS
    echoOk "Share $shareName $clientIp added"
    chmod 777 $shareName
  else
    # share exist, check if client is added
    checkShareClient "$result" "$clientIp"
    if [[ $? -eq 0 ]]; then
      #client doesn't exist, adding...
      result="${result} $clientIp(rw,sync,no_subtree_check)"
      #FIXME sed doesn't take $result, hidden ascii?

      #save the rest of the doc
      echo $(cat $EXPORTS | grep -v $shareName) > $EXPORTS
      echo $result >> $EXPORTS
      echoOk "Share $shareName $clientIp added"
    else
      # client already exists
      echoError "Share  $shareName $clientIp already exist" && exit 1
    fi
  fi
 
  # add the user to the white list
  checkIpInWhitelist $clientIp
  if [[ $? -eq 0 ]]; then
    sed -i "s/$/ $clientIp ,/" $ALLOW
    echoOk "$clientIp added to the white list" 
  fi

  # restart service
  service rpcbind restart &>/dev/null
  if [[ $? -eq 0 ]]; then
    echoOk "Service rpcbind restarted"
  else
    echoError "Service rpcbind restart failed" && exit 1
  fi

  service nfs-kernel-server restart &>/dev/null
  if [[ $? -eq 0 ]]; then
    echoOk "Service NFS restarted"
  else
    echoError "Service NFS restart failed" && exit 1
  fi

}

##########################################
#               removeShare

# Remove a share
removeShare()
{
 echo $(cat $EXPORTS | grep -v $shareName) > $EXPORTS
 echoOk "$shareName has been deleted"

 # restart service
  service rpcbind restart &>/dev/null
  if [[ $? -eq 0 ]]; then
    echoOk "Service rpcbind restarted"
  else
    echoError "Service rpcbind restart failed" && exit 1
  fi

  service nfs-kernel-server restart &>/dev/null
  if [[ $? -eq 0 ]]; then
    echoOk "Service NFS restarted"
  else
    echoError "Service NFS restart failed" && exit 1
  fi

}

##########################################
#               removeShareClient

# Remove a client from a share
removeShareClient()
{
 #get the ligne of our share
 currentShare=$(grep "$shareName " $EXPORTS)
 #save the rest of the doc
 echo $(cat $EXPORTS | grep -v $shareName) > $EXPORTS
 
 # remove the client
 currentShare=$(echo $currentShare | sed "s/$clientIp(rw,sync,no_subtree_check)//")
 if [[ $currentShare == "$shareName " ]]; then
   # no client left, removing
   echoOk "No more client, $shareName has been removed"
 else
   # saving share
   echo $currentShare >> $EXPORTS
   echoOk "client $clientIp has been removed from $shareName"
 fi

 # remove the user the user from the white list
 checkShareClient $EXPORTS $clientIp
 if [[ $? -eq 0 ]]; then
   # no more share with this user, removing it
   sed -i "s/$clientIp ,//" $ALLOW
   echoOk "$clientIp removed from the white list"
 else
   echoInfo "$clientIp still in the white list to access to others shares"
 fi

# restart service
  service rpcbind restart &>/dev/null
  if [[ $? -eq 0 ]]; then 
    echoOk "Service rpcbind restarted"
  else
    echoError "Service rpcbind restart failed" && exit 1
  fi
  
  service nfs-kernel-server restart &>/dev/null
  if [[ $? -eq 0 ]]; then
    echoOk "Service NFS restarted"
  else
    echoError "Service NFS restart failed" && exit 1
  fi
  

}


##########################################
#
# 		Main
#
##########################################

# Starting to log
echo -e "$DATE\n$TIME" > $LOG

# Before exiting show the log path
trap finish EXIT

# Check arguments & launch options checking
while getopts "hiuars:c:" option
do
  case $option in
  
  # Only one main option can be selected thanks to DOIT value

    # show help
    h)
      [[ DOIT -eq 1 ]] && bad_Parameters
      DOIT=1 && opt_usage=1
      ;;
    # install 
    i)
      [[ DOIT -eq 1 ]] && bad_Parameters
      DOIT=1 && opt_install=1
      ;;
    # uninstall
    u)
      [[ DOIT -eq 1 ]] && bad_Parameters
      DOIT=1 && opt_uninstall=1
      ;;
    # add a share
    a)
      [[ DOIT -eq 1 ]] && bad_Parameters
      DOIT=1 && opt_addShare=1
      ;;
    # remove a share
    r)
      [[ DOIT -eq 1 ]] && bad_Parameters
      DOIT=1 && opt_removeShare=1
      ;;
    # select a share name
    s)
      shareName=$OPTARG
      ;;
    # select a client IP
    c)
      clientIp=$OPTARG
      DOITIP=1
      ;;
    # invalid option
    \?)
       echo "option invalide ---"
       bad_Parameters
       ;;
  esac
done

# No parameters show usage
[[ "$DOIT" -ne 1 ]] && bad_Parameters


# Checking if user is root
checkRoot

##########################################
#	   Installation

# update packages list and install 
[[ $opt_install -eq 1 ]] && updatePackagesList && installPackageNfs

##########################################
#          Removal
[[ $opt_uninstall -eq 1 ]] && uninstallPackageNfs


##########################################
#          Adding a share
if [[ $opt_addShare -eq 1 ]]; then
  # check for a valid path
  [[ ! -d $shareName ]] && echoError "share path doesn't exist" && exit 1
  
  # check for a valid IP
  checkIp $clientIp
  [[ $? -eq 0 ]] && echoError "IP is not valid" && exit 1
  
  addShare
fi

##########################################
#          Removing a share
if [[ $opt_removeShare -eq 1 ]]; then
  # check if share exist
  result=$(checkShare $shareName)
  [[ "$result" == "0" ]] && echoError "Share doesn't exist" && exit 1
  
  # check if we are dealing with the whole share or a client
  if [[ $DOITIP -eq 1 ]]; then
    removeShareClient
  else
    # remove the share
    removeShare
  fi
fi


exit 0


