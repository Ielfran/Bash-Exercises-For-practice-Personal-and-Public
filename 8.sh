#!/bin/bash

read -p "Enter the brand name of the car:" car
case $car in 
    Tesla)
        echo -n "${car}'s made in the USA"
        ;;

    BMW | Mercedes | Audi)
        echo -n "${car}'s made in Germany"
        ;;
    Toyota | Honda)
        echo -n "${car}'s made in Japan"
        ;;

    *)
        echo -n "${car}'s dont know this"
        ;;
esac
