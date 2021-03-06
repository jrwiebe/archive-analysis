#!/usr/bin/env bash
# Author: vinay

# Runs a Hadoop Streaming Job to generate OUTLINKS files
# for WARC files stored in a HDFS directory.
# Finds the set of WARC files that do not have a corresponding OUTLINKS file
# and generates OUTLINKS files for this set

if [ $# != 4 ] ; then
    echo "Usage: TOOL <HDFSWARCDIR> <HDFSOUTLINKSDIR> <HDFSWORKDIR> <LOCALWORKDIR>"
    echo "HDFSWARCDIR: HDFS directory location containing WARC files"
    echo "HDFSOUTLINKSDIR: HDFS directory location for the resulting OUTLINKS files"
    echo "HDFSWORKDIR: HDFS directory location for scratch space (will be created if non-existent)"
    echo "LOCALWORKDIR: Local directory for scratch space (will be created if non-existent)"
    exit 1
fi

HDFSWARCDIR=$1
HDFSOUTLINKSDIR=$2
HDFSWORKDIR=$3
LOCALWORKDIR=$4

#HADOOP_HOME=/home/webcrawl/hadoop-0.20.2-cdh3u3/
PROJECTDIR=`pwd`

JOBNAME=OUTLINKS-Generator
HADOOPCMD=$HADOOP_HOME/bin/hadoop
HADOOPSTREAMJAR=$HADOOP_HOME/contrib/streaming/hadoop-streaming-*.jar
TASKTIMEOUT=3600000

MAPPERFILE=$PROJECTDIR/hadoop-streaming/warc-metadata-outlinks/generate-outlinks-mapper.sh
MAPPER=generate-outlinks-mapper.sh

#create HDFSOUTLINKSDIR
$HADOOPCMD fs -mkdir $HDFSOUTLINKSDIR 2> /dev/null

#create task dir in HDFS
UPDATENUM=`date +%s`
TASKDIR=$HDFSWORKDIR/$UPDATENUM
$HADOOPCMD fs -mkdir $TASKDIR

mkdir -p $LOCALWORKDIR
if [ $? -ne 0 ]; then
    echo "ERROR: unable to create $LOCALWORKDIR"
    exit 2
fi

#dump list of WARC files (only prefixes)
$HADOOPCMD fs -ls $HDFSWARCDIR | grep warc.gz$ | tr -s ' ' | cut -f8 -d ' ' | awk -F'/' '{ print $NF }' | sort | uniq | sed "s@.warc.gz@.warc@" > $LOCALWORKDIR/warcs.list 

#dump list of OUTLINKS files already generated (only prefixes)
$HADOOPCMD fs -ls $HDFSOUTLINKSDIR | grep outlinks.gz$ | tr -s ' ' | cut -f8 -d ' ' | awk -F'/' '{ print $NF }' | sort | uniq | sed "s@.warc.outlinks.gz@.warc@"  > $LOCALWORKDIR/outlinkss.list 

# find list of prefixes to be processed
join -v1 $LOCALWORKDIR/warcs.list $LOCALWORKDIR/outlinkss.list > $LOCALWORKDIR/todo.list

# if todo.list is empty, exit
if [[ ! -s $LOCALWORKDIR/todo.list ]] ; then echo "No new WARCs to be processed"; rm -f $LOCALWORKDIR/warcs.list $LOCALWORKDIR/outlinkss.list $LOCALWORKDIR/todo.list; exit 0; fi

#create task file from todo.list
cat $LOCALWORKDIR/todo.list | sed "s@\$@ $HDFSWARCDIR $HDFSOUTLINKSDIR@" | $PROJECTDIR/bin/unique-sorted-lines-by-first-field.pl > $LOCALWORKDIR/taskfile

num=`wc -l $LOCALWORKDIR/taskfile | cut -f1 -d ' '`;
echo "Number of new WARCs to be processed - $num";

#store task file in HDFS
$HADOOPCMD fs -put $LOCALWORKDIR/taskfile $TASKDIR/taskfile

INPUT=$TASKDIR/taskfile
OUTPUT=$TASKDIR/result

echo "Starting Hadoop Streaming job to process $num WARCs";
# run streaming job - 1 mapper per file to be processed
$HADOOPCMD jar $HADOOPSTREAMJAR -D mapred.job.name=$JOBNAME -D mapred.reduce.tasks=0 -D mapred.task.timeout=$TASKTIMEOUT -D mapred.line.input.format.linespermap=1 -inputformat org.apache.hadoop.mapred.lib.NLineInputFormat -input $INPUT -output $OUTPUT -mapper $MAPPER -file $MAPPERFILE

if [ $? -ne 0 ]; then
    echo "ERROR: streaming job failed! - $INPUT"
    rm -f $LOCALWORKDIR/warcs.list $LOCALWORKDIR/outlinkss.list $LOCALWORKDIR/todo.list $LOCALWORKDIR/taskfile
    exit 3
fi

rm -f $LOCALWORKDIR/warcs.list $LOCALWORKDIR/outlinkss.list $LOCALWORKDIR/todo.list $LOCALWORKDIR/taskfile
echo "OUTLINKS Generation Job complete - per file status in $OUTPUT";

