#!/bin/bash
CLUSTER_NAME="rolling-update-test";
OLD_NODE_GROUP_NAME="old";
NEW_NODE_GROUP_NAME="new";
NEW_INSTANCE_TYPE="m5.large";
AMI_TYPE="AL2_x86_64"; # or AL2_ARM_64
GRACE_PERIOD="15"; # Grace Period of Kubernetes. If negative, the default value specified in the pod will be used.
SLEEP_TIME="15"; # Sleep Time Between Draining Nodes

# Check if jq exist
if [ $(dpkg-query -W -f='${Status}' jq 2>/dev/null | grep -c "ok installed") -eq 0 ];
then
    sudo apt-get install jq -y;
fi

# Get Old Node Group Information
OLD_NODE_GROUP_INFO=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $OLD_NODE_GROUP_NAME | jq -r .nodegroup);

# Create New Node Group
aws eks create-nodegroup \
    --cluster-name $CLUSTER_NAME \
    --nodegroup-name $NEW_NODE_GROUP_NAME \
    --subnets "$(echo $OLD_NODE_GROUP_INFO | jq -r .subnets)" \
    --node-role "$(echo $OLD_NODE_GROUP_INFO | jq -r .nodeRole)" \
    --scaling-config "$(echo $OLD_NODE_GROUP_INFO | jq -r .scalingConfig)" \
    --disk-size "$(echo $OLD_NODE_GROUP_INFO | jq -r .diskSize)" \
    --instance-types "[\"$NEW_INSTANCE_TYPE\"]" \
    --ami-type "$AMI_TYPE" \
    --labels "$(echo $OLD_NODE_GROUP_INFO | jq -r .labels)" \
    --tags "$(echo $OLD_NODE_GROUP_INFO | jq -r .tags)" \
    --remote-access "$(echo $OLD_NODE_GROUP_INFO | jq -r .remoteAccess)" > /dev/null && \
echo "Creating new node group..." && \
aws eks wait nodegroup-active --cluster-name $CLUSTER_NAME --nodegroup-name $NEW_NODE_GROUP_NAME;

# Drain Old Nodes
NEW_NODE_STAT=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NEW_NODE_GROUP_NAME | jq -r .nodegroup.status)
if [[ "$NEW_NODE_STAT" == "ACTIVE" ]];
then
    echo "Draining old nodes..."
    kubectl get nodes -l eks.amazonaws.com/nodegroup=$OLD_NODE_GROUP_NAME -o name | \
    while read prefix_name;
    do
        name=$(sed -e 's#.*/\(\)#\1#' <<< "$prefix_name");
        kubectl drain $name --grace-period=$GRACE_PERIOD;
        sleep $SLEEP_TIME;
    done;

    sleep 10
    # Delete Old Node Group
    echo "Deleting Old Node Group..."
    aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $OLD_NODE_GROUP_NAME > /dev/null;
    aws eks wait nodegroup-deleted --cluster-name $CLUSTER_NAME --nodegroup-name $OLD_NODE_GROUP_NAME && \
    echo "Old Node Group Deleted!"
else
    echo "There are some problems with new node group TAT"
fi