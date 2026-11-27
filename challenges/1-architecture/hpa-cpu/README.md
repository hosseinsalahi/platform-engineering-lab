# Configure Horizontal Pod Autoscaling

**Time:** 7 minutes
**Skills tested:** Kubernetes HPA, Scaling, Metrics

## Context

The `cnpe-scaling` namespace contains a web application `php-apache` that suffers from performance issues during high load.
You need to configure autoscaling to handle traffic spikes.

## Task

Create a HorizontalPodAutoscaler named `php-apache-hpa` in namespace `cnpe-scaling` that scales the `php-apache` deployment:

1.  **Min Replicas:** 2
2.  **Max Replicas:** 10
3.  **Target Metric:** Average CPU utilization of 50%

## Verification

The exercise validates:
1.  HPA resource exists
2.  Target reference is correct
3.  Min/Max replicas are correct
4.  CPU target is set to 50%

## Allowed Documentation

- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
