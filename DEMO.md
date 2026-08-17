# WAF Status

WAF is deployed and left running continuously (~$8/month) so the app is always demo-ready without any manual toggling before interviews - budgeted around $10 total, covering roughly 5-6 weeks.

## When you're done with the project (or want to cut the cost)
Remove just the WAF piece - everything else (app, database, load balancer, monitoring) keeps running normally:

```bash
cd terraform
export TF_VAR_db_password='<your db password>'
terraform destroy -target=aws_wafv2_web_acl_association.main -target=aws_wafv2_web_acl.main
```

The app stays reachable at the same load balancer URL either way (`terraform output app_url`) - destroying WAF just removes the request-filtering layer, not the app itself.
