## Update cloudfront for new media
### Fix 1
You need to edit the **Cache Policy** associated with the **Behavior** that serves your content.

1.  Navigate to your **CloudFront Distribution**.
2.  Go to the **Behaviors** tab.
3.  Select the behavior for your images (e.g., `Default (*)`) and click **Edit**.
4.  Find the **Cache key and origin requests** section.
5.  Look at the selected **Cache policy**. The default policy, `CachingOptimized`, does **not** include query strings. You must change this.
6.  You have two main options:
    * **Use a Managed Policy:** Select a pre-configured AWS policy that forwards query strings, such as `AllViewer`.
    * **Create a Custom Policy (Recommended ✅):** Click "Create policy" to make your own. In the settings:
        * Under **Cache key settings** -> **Query strings**, choose **"Allow list"**.
        * Add `v` to the allow list. This is the most efficient option as it tells CloudFront to only care about your versioning parameter and ignore any others. Alternatively, you can choose "All".

### Fix 2
```javascript
import { CloudFrontClient, CreateInvalidationCommand } from "@aws-sdk/client-cloudfront";

// 1. Configure the CloudFront Client
const cfClient = new CloudFrontClient({ region: "us-east-1" }); // Note: CloudFront API is global, use us-east-1

// 2. Define the invalidation parameters
const distributionId = 'E123ABC456DEF'; // Your CloudFront Distribution ID
const objectKey = '/images/profile-pic.jpg'; // The path to the object, must start with a '/'

const params = {
  DistributionId: distributionId,
  InvalidationBatch: {
    Paths: {
      Quantity: 1,
      Items: [objectKey] // Array of paths to invalidate
    },
    CallerReference: `invalidation-${Date.now()}` // A unique string for this request
  }
};

// 3. Send the command
try {
  const command = new CreateInvalidationCommand(params);
  const data = await cfClient.send(command);
  console.log('Invalidation created successfully:', data.Invalidation.Id);
} catch (err) {
  console.error('Error creating invalidation:', err);
}
```
