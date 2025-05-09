#!/bin/bash

# Пути к файлам (хардкод)
MSI_FILE="C:/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop-SetupFiles/Neuro_Desktop-3.0.30-431.msi"
EXTRACT_DIR="C:/Users/BlackBricks/Applications/Neuro installer/installer_win/Neuro Desktop-SetupFiles/Neuro_Desktop-3.0.30-431"

mkdir -p "$EXTRACT_DIR"
lessmsi x "$MSI_FILE" "$EXTRACT_DIR"

echo "Extraction completed to: $EXTRACT_DIR"