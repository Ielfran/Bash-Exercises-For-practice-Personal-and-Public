#!/bin/bash

users="This is the end"
for user in ${users}
do
    echo "${user}"
done



for num in {1..10}
do
    echo "${num}"
done



a=1
while [[ $a -le 10 ]]
do
    echo "${a}"
    ((a++))
done



read -p "what is the name of the website" web
while [[ -z ${web} ]] 
do
    echo "Your website's name cannot be empty"
    read -p "Try to write the name again" web
done 
echo "The name is ${name}"


b=1
until [[ $b -gt 10 ]]
do
    echo $b
    (($b==))
done
