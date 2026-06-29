# CDK パターン集

## App Runner + RDS

```typescript
import * as cdk from 'aws-cdk-lib'
import * as apprunner from '@aws-cdk/aws-apprunner-alpha'
import * as ec2 from 'aws-cdk-lib/aws-ec2'

export class ComputeStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props: ComputeStackProps) {
    super(scope, id, props)

    const vpcConnector = new apprunner.VpcConnector(this, 'VpcConnector', {
      vpc: props.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
    })

    new apprunner.Service(this, 'AppRunner', {
      source: apprunner.Source.fromEcr({
        repository: props.ecrRepository,
        tagOrDigest: 'latest',
      }),
      cpu: apprunner.Cpu.ONE_VCPU,
      memory: apprunner.Memory.TWO_GB,
      vpcConnector,
    })
  }
}
```

## Lambda + API Gateway

```typescript
import * as cdk from 'aws-cdk-lib'
import * as lambda from 'aws-cdk-lib/aws-lambda'
import * as apigw from 'aws-cdk-lib/aws-apigateway'

export class ApiStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string) {
    super(scope, id)

    const fn = new lambda.Function(this, 'Handler', {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset('lambda'),
    })

    new apigw.LambdaRestApi(this, 'Api', { handler: fn })
  }
}
```

## ECS Fargate + ALB

```typescript
import * as cdk from 'aws-cdk-lib'
import * as ecsPatterns from 'aws-cdk-lib/aws-ecs-patterns'

export class FargateStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string, props: FargateStackProps) {
    super(scope, id, props)

    new ecsPatterns.ApplicationLoadBalancedFargateService(this, 'Service', {
      cluster: props.cluster,
      taskImageOptions: {
        image: ecs.ContainerImage.fromEcrRepository(props.ecrRepository),
        containerPort: 8080,
      },
      desiredCount: 2,
      publicLoadBalancer: true,
    })
  }
}
```

## 共通: VPC 構成

```typescript
const vpc = new ec2.Vpc(this, 'Vpc', {
  maxAzs: 2,
  natGateways: 1,
  subnetConfiguration: [
    { name: 'Public', subnetType: ec2.SubnetType.PUBLIC, cidrMask: 24 },
    { name: 'Private', subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS, cidrMask: 24 },
    { name: 'Isolated', subnetType: ec2.SubnetType.PRIVATE_ISOLATED, cidrMask: 24 },
  ],
})
```
