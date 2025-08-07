# Railway Deployment Guide

## Quick Deployment Steps

1. **Go to Railway Dashboard**: https://railway.app/new
2. **Deploy from GitHub**:
   - Connect this repository
   - Railway will auto-detect the Dockerfile
   - Choose the `backend/` directory as the root

3. **Set Environment Variables** in Railway dashboard:
   ```
   OPENAI_API_KEY=your-openai-api-key-here
   
   API_KEY=add2wallet-prod-4fafa87d63f30ecc38e1a156bcb240d6
   
   DEBUG=false
   LOG_LEVEL=INFO
   ```

4. **Add Apple Wallet Certificates** (base64 encoded):
   - Copy the certificate values from Vercel environment variables
   - Or get them from the local certificates folder:
   
   ```bash
   # Generate base64 certificates
   base64 -i certificates/pass.pem | tr -d '\n'  # Copy to PASS_CERT_PEM
   base64 -i certificates/key.pem | tr -d '\n'   # Copy to PASS_KEY_PEM  
   base64 -i certificates/wwdrg4.pem | tr -d '\n' # Copy to WWDR_CERT_PEM
   ```

5. **Deploy**: Railway will automatically build and deploy

## Expected Results

✅ **Full Functionality**:
- AI-powered PDF analysis with OpenAI
- Complete barcode/QR extraction with OpenCV + pyzbar
- PDF to image conversion with pdf2image  
- PyMuPDF vector barcode detection
- Apple Wallet certificate signing
- Multi-ticket support
- Real-time processing

✅ **No degraded experience** - same as local development
✅ **Docker-based deployment** - handles all binary dependencies
✅ **Auto-scaling** and health checks
✅ **Custom domain** support available

## Health Check

Once deployed, test the health endpoint:
```bash
curl https://your-railway-domain.railway.app/health
```

Should return all services as "initialized" or "enabled".