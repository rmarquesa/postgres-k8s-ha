# Sealed Secrets operations runbook

## Rules

- one controller key set per physical cluster;
- strict scope for production manifests;
- different credentials per environment;
- no plaintext Secret YAML, password, private key or decrypted output in Git, logs or evidence;
- CloudNativePG-managed internal certificates/Secrets remain operator-owned.

## Create or rotate an application/S3 Secret

1. Load the new value from the approved password manager into environment variables.
2. Confirm `KUBECONFIG` and exact `EXPECTED_CONTEXT`.
3. Run `scripts/seal-production-secret.sh` for the logical Secret.
4. Validate and commit only the `.sealed.yaml` output.
5. Apply and verify only Secret metadata/keys.
6. Restart/reload the consuming workload through its supported rotation procedure.
7. Revoke the previous credential after all consumers use the new value.

Rotating the controller sealing key does not automatically rotate database/S3 credentials.

## Back up controller keys

Stream the labelled key Secrets directly into the approved encrypted external vault. Example with `age`:

```bash
umask 077
kubectl -n kube-system get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml |
  age -r "$AGE_RECIPIENT" > /approved/external/location/sealed-secrets-keys.yaml.age
```

The destination must be outside this repository, access-controlled, audited and backed up. Verify the encrypted artifact checksum and recoverability without printing decrypted content.

## Restore controller keys

1. Use an isolated recovery cluster.
2. Install the same or a compatible controller version without creating production Secrets.
3. Decrypt the backup directly into `kubectl apply` through a pipe.
4. Restart the controller and wait for readiness.
5. Apply a disposable previously sealed test resource and verify materialization.
6. Delete the disposable namespace and record the drill evidence.

Do not test private-key recovery in the active production controller namespace without an approved change.

## Compromise

If sealing keys are exposed, treat every Secret encrypted by those keys as exposed: rotate S3/database/integration credentials, install a new controller key, reseal all manifests, revoke old credentials and preserve audit evidence. Removing only the old Kubernetes key Secret is insufficient.
