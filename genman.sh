#!/bin/bash
cp bugd.1.template bugd.1

sed -i '/<synopsis>/{
r doc/synopsis.txt
d
}' bugd.1

#replace newlines with .br for the makefile
sed 's/$/\n.br/g' doc/usage.txt > bugd.1.usage

sed -i '/<usage>/{
r bugd.1.usage
d
}' bugd.1
