#!/bin/bash

set -e

kubectl patch svc -n istio-system istio-ingressgateway -p '{"spec":{"externalIPs":["10.10.13.87"]}}'

