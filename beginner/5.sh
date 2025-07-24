my_array=("value 1","value 2","value 3")

echo "${my_array[0]}"
echo "${my_array[-1]}"


#string slicing

text="ABCD"

echo "${text:0:2}"
echo "${text:1:2}"
echo "${text:2:2}"
