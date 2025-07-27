#!/bin/bash

echo "Enter the first number:"
read num1
echo "Enter the second number:"
read num2

echo "Select operation: +, -, *, /"
read op

case $op in
    +) result=$(($num1 + $num2));;
    -) result=$(($num1 - $num2));;
    \*) result=$(($num1 * $num2));;
    /) 
        if [ $num2 -eq 0 ]; then
            echo "Division by zero is not allowed."
            exit 1
        else
            result=$(($num1 / $num2))
        fi
        ;;
    *) echo "Invalid operation"; exit 1;;
esac

echo "The result of $num1 $op $num2 is: $result"
