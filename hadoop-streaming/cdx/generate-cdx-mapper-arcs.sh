#!/usr/bin/env bash
# Author: vinay

# Mapper: Generate and Store CDX files
PROJECTDIR=`pwd`

HDFSCMD=$HADOOP_HOME/bin/hdfs
IAHADOOPTOOLS=./ia-hadoop-tools-jar-with-dependencies.jar

#replace exit statements with continue if you want Job to proceed despite some failures
while read lineoffset arcbase arcdir cdxdir; do

	#lineoffset is ignored	
	$HDFSCMD dfs -get $arcdir/$arcbase.gz .
	copystatus=$?
	if [ $copystatus -ne 0 ]; then 
		rm -f $arcbase.gz
		echo "$arcbase arc-copy-fail $copystatus"
		exit 1
        fi

	java -Xmx2048m -jar $IAHADOOPTOOLS extractor -cdx $arcbase.gz > $arcbase.cdx;
	cdxstatus=$?
	if [ $cdxstatus -ne 0 ]; then
                rm -f $arcbase.gz $arcbase.cdx;
                echo "$arcbase cdx-gen-fail $cdxstatus"
                exit 2
        fi

	gzip $arcbase.cdx;
	cdxstatus=$?
	if [ $cdxstatus -ne 0 ]; then
                rm -f $arcbase.gz $arcbase.cdx.gz;
                echo "$arcbase cdx-gz-fail $cdxstatus"
                exit 3
        fi

	$HDFSCMD dfs -put $arcbase.cdx.gz $cdxdir/$arcbase.cdx.gz
	storestatus=$?
	if [ $storestatus -ne 0 ]; then
                rm -f $arcbase.gz $arcbase.cdx.gz;
		$HDFSCMD dfs -rm $cdxdir/$arcbase.cdx.gz
                echo "$arcbase cdx-store-fail $storestatus"
                exit 4
        fi
	
	rm -f $arcbase.gz $arcbase.cdx.gz;
	echo "$arcbase success 0";
done

