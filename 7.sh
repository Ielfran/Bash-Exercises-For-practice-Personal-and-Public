#!/bin/bash
admin="Ielfran"
read -p "What is the name:" name
if [[ "${name}" == "${admin}" ]] ;then 
    echo "You are the admin"
else
    echo "Not the admin"
fi
if (( $EUID == 0 )); then
    echo "Please not the root"
    exit
fi
