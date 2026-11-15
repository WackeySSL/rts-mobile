# app-ads.txt

AdMob expects an `app-ads.txt` file so buyers can verify who may sell this app's ads (to confirm against
Google's current AdMob help page for app-ads.txt).

## The line
Exact format, with the placeholder publisher ID (replace with the real AdMob publisher ID from M8):

```
google.com, pub-0000000000000000, DIRECT, f08c47fec0942fa0
```

The last field is Google's certification authority ID (to confirm).

## Where it goes
- File URL: `https://appcode.dk/app-ads.txt` (domain root, plain text, one line per seller).
- The Play listing's developer website must be `https://appcode.dk`, so the file is found at that domain (to confirm).
- AdMob crawls it after the app is listed; its "verified" status can take time (to confirm). Link the app in AdMob
  once listed (M11).
