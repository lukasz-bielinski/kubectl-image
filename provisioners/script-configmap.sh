#!/bin/bash
. /provisioners/functions
func_initialize_check_force_update

echo "Provisioner for $PROV_TYPE is starting.."
echo ""

cleanup ()
{
  kill -s SIGTERM $!
  exit 0
}

trap cleanup SIGINT SIGTERM
lockfile=/tmp/lock.kubectl


#wait until configmaplist fill be created
while [ ! -f /tmp/configmaplist.txt ]
do
  sleep 2
  echo "There is no file with configmap list yet"
  ###create configmaplist with hashes, avoid deleteing pods during startup
  dir=/src/$CONFIGMAPS_DIR
  nsList=$(ls -d $dir*/*/*/)
  # echo $nsList

  for i in $nsList
  do
    hash=$(find $i -type f -name "*" -not -path "*.git*" -exec md5sum {} + | awk '{print $1}' | sort | md5sum | awk '{ print $1 }')
    echo "$hash  $i  " >> /tmp/configmaplist.txt
  done

done

#avoid deleteing pods during startup
date=$(date -I'seconds')
echo "Initial list was created at $date"

###run provisioning  process
while [ 1 ]
do
  sleep $[ ( $RANDOM % 20 )  + 1 ]s &
  wait $!

  ############ configmap
  dir=/src/$CONFIGMAPS_DIR
  nsList=$(ls -d $dir*/*/*/)
  # echo $nsList

  #create list with hashes of configmap dirs inside on ns dirs
  for i in $nsList
  do
    hash=$(find $i -type f -name "*" -not -path "*.git*" -exec md5sum {} + | awk '{print $1}' | sort | md5sum | awk '{ print $1 }')
    # echo   $i
    # echo $hash
    echo "$hash  $i  " >> /tmp/configmaplist.new.txt
  done
  comm -1 -3 <(sort /tmp/configmaplist.txt) <(sort /tmp/configmaplist.new.txt) > /tmp/configmaplist.process.txt

  #delete pods, which uses changed configmap. wait after delete 60s
  while read secline
  do

    SUBSTRING=$(echo $secline|  cut -d' '  -f2)
    secName=$(basename $SUBSTRING)
    NS=$(basename $(dirname $SUBSTRING))
    date=$(date -I'seconds')
    echo "$date configmap $secName in $NS was changed. It will be deleted"
    kubectl --namespace=$NS delete configmap $secName
    sleep 1
    date=$(date -I'seconds')
    echo "$date configmap $secName in $NS will be created"
    kubectl --namespace=$NS create configmap  $secName --from-file=$SUBSTRING

    #generic solution
    podlist=$(kubectl --namespace=$NS get pods -o json |  jq --arg secret $secName '.items[] | select(.spec.volumes[].configMap.name == $secret).metadata.name')

    for i in $podlist
    do
      echo "pod list using configmap $secName is $podlist "
      echo ""
      echo "currently processed pod $i"
      i=$(echo "$i" | tr -d '"')
      date=$(date -I'seconds')
      echo "$date Deleting pod $i in namespace $NS using configmap $secName "
      kubectl --namespace=$NS delete pod    $i
      sleep 6

    done

  done < /tmp/configmaplist.process.txt

  mv /tmp/configmaplist.new.txt  /tmp/configmaplist.txt



done
