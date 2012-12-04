#!/usr/bin/env bash

MODULE=`perl -ne 'print($1),exit if m{version_from.+?([\w/.]+)}i' Makefile.PL`;
perl=perl
$perl -v

rm -rf MANIFEST.bak Makefile.old *.tar.gz && \
pod2text $MODULE > README && \
$perl -i -lpne 's{^\s+$}{};s{^    ((?: {8})+)}{" "x(4+length($1)/2)}se;' README && \
$perl Makefile.PL && \
make manifest && \
make && \
#TEST_AUTHOR=1 make test && \
#TEST_AUTHOR=1 runprove 'xt/*.t' && \
cp MYMETA.yml META.yml && \
cp MYMETA.json META.json && \
make disttest && \
make dist && \
cp -f *.tar.gz dist/ && \
make clean && \
#$perl Makefile.PL && \
#make && \
#makerpm && \
#make clean && \
#rm -rf MANIFEST.bak Makefile.old && \
#$perl Makefile.PL && \
#cp MYMETA.yml META.yml && \
#cp MYMETA.json META.json && \
echo "All is OK"
