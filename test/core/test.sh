echo test $1 >> test.log
echo compiling $1

rm -f $1.out
../../src/lib/coreasm $1    >>$1.out  2>>$1.out

echo running $1
../../src/runtime/lvmrun -S200k -H4M $1 >>$1.out   2>>$1.out

if compare $1.out $1.ok >> /dev/null; then
echo ok
else
echo -- error --
cat $1.out
compare $1.out $1.ok
echo -----------
echo -- error -- >> test.log
cat $1.out	 >> test.log
compare $1.out $1.ok >> test.log 2>> test.log;
echo ----------- >> test.log
fi

#echo >> test.log
echo
