#!/bin/bash

echo "Enter the starting number:"
read start
echo "Enter the ending number:"
read end

for (( i=$start; i<=$end; i++ ))
do
    echo $i
done
