#!/bin/bash

# Set the image name
IMAGE_NAME="meticulous_docker_host_image"

echo -e "\033[93mBuilding Docker image...\033[0m"

docker build -t $IMAGE_NAME -f image-builder.Dockerfile .

echo -e "\033[93mRunning container...\033[0m"

docker run -it --rm -v "$(pwd):/meticulous" $IMAGE_NAME bash
