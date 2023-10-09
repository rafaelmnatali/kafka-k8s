#!/bin/bash
set +xoe pipefail

#########################################################################################
# 
# This script uses Kafka's partition reassignment tool to move partitions across brokers.
# Kafka Docs reference:
# https://kafka.apache.org/26/documentation.html#basic_ops_cluster_expansion
#
# Usage:
#
# Create a text file (kafka-topics.txt) with the list of Kafka topics to reassign
# chmod +x ./kafka-reassign.sh
# ./kafka-reassign.sh
#########################################################################################

output_dir="./output"
[ -d $output_dir ] || mkdir $output_dir

banner()
{
  echo "+------------------------------------------+"
  printf "| %-40s |\n" "`date`"
  printf "| %s \n" "${@//[$'\t\r\n']}"
  echo "+------------------------------------------+"
}

input="kafka-topics.txt"
while IFS= read -r line
do
  banner "Starting Topic ${line//[$'\t\r\n']}"

  echo -e "\nReplacing topic in JSON template"
  sed -e "s/<TOPIC>/${line//[$'\t\r\n']}/g" template.json > $output_dir/topics.json

  echo -e "\nGenerating and cleaning reassign.json"
  kafka-reassign-partitions --bootstrap-server ${BOOTSTRAP_SERVER} --topics-to-move-json-file $output_dir/topics.json --broker-list "0,1,2,3,4"  --generate  | awk '/Proposed partition reassignment configuration/{c=NR+2}(NR<=c){print}' | awk NR\>1 > $output_dir/reassign.json 
  
  echo -e "\nExecuting reassignment"
  kafka-reassign-partitions --bootstrap-server ${BOOTSTRAP_SERVER}  --reassignment-json-file $output_dir/reassign.json  --execute 
  
  echo -e "\nVerifying reassignment"
  kafka-reassign-partitions --bootstrap-server ${BOOTSTRAP_SERVER}  --reassignment-json-file $output_dir/reassign.json  --verify 
  count=$(kafka-reassign-partitions --bootstrap-server ${BOOTSTRAP_SERVER}  --reassignment-json-file $output_dir/reassign.json  --verify  | grep -o "still in progress" | wc -l)
  echo "partition reassignment in progress: $count"
  while [ $count -gt 0 ]
  do
    sleep 5
    count=$(kafka-reassign-partitions --bootstrap-server ${BOOTSTRAP_SERVER}  --reassignment-json-file $output_dir/reassign.json --verify | grep -o "still in progress" | wc -l)
    echo "partition reassignment in progress: $count"
  done
done < "$input"