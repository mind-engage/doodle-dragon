const { onRequest } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { defineSecret } = require('firebase-functions/params');
const functions = require('firebase-functions');
const { OpenAI } = require('openai'); 
const axios = require('axios');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require("firebase-admin/firestore");
const admin = require('firebase-admin');

// Initialize Firebase app
initializeApp();

// Define secrets (keys)
const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

// Middleware to verify Firebase Authentication token
const authenticateRequest = async (req, res, next) => {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Unauthorized' });
    }

    const idToken = authHeader.split('Bearer ')[1];

    try {
        const decodedToken = await getAuth().verifyIdToken(idToken);
        req.user = decodedToken; // Attach user information to the request
        next();
    } catch (error) {
        console.error('Authentication error:', error);
        return res.status(403).json({ error: 'Forbidden' });
    }
};


exports.initNewUser = functions.auth.user().onCreate((user) => {
  const newUser = {
    uid: user.uid,
    totalTokensConsumed: 0,
    totalTokenLimit: 1000,  // Default limit
    // other default settings
  };

  return admin.firestore().collection('users').doc(user.uid).set(newUser)
    .then(() => {
      console.log('User initialized successfully:', user.uid);
    })
    .catch(error => {
      console.error('Error initializing user:', error);
    });
});

// Proxy request to OpenAI API
exports.proxyOpenAI = onRequest({ cors: true, secrets: [OPENAI_API_KEY] }, async (req, res) => {
    if (req.method !== 'POST') {
        return res.status(405).send('Method Not Allowed');
    }

    try {

        // Authenticate request
        await authenticateRequest(req, res, () => {});

        // Access OpenAI API key
        const openaiApiKey = OPENAI_API_KEY.value();

        const openai = new OpenAI({
            apiKey: openaiApiKey,
         });
         
         console.log(req.body);

         const { prompt, n = 1, size = '1024x1024', responseFormat = 'b64_json' } = req.body;
        // Call OpenAI's image generation endpoint
        const response = await openai.images.generate({
            prompt: prompt,
            n: n,
            size: size, // Map the enum value (e.g., '1024x1024')
            response_format: responseFormat, // b64_json or url
         });
        // Make a POST request to OpenAI API
        res.json(response.data);
    } catch (error) {
        console.error('Error in OpenAI request:', error);
        res.status(500).json({ error: 'Failed to contact OpenAI API' });
    }
});

// Proxy request to Gemini API
exports.proxyGemini = onRequest({ cors: true, secrets: [GEMINI_API_KEY] }, async (req, res) => {
    if (req.method !== 'POST') {
        return res.status(405).send('Method Not Allowed');
    }

    try {
        // Authenticate request
        await authenticateRequest(req, res, () => {});

        // Retrieve user's token usage and limit from Firestore
        const db = getFirestore();
        const userRef = db.collection('users').doc(req.user.uid);
        const userDoc = await userRef.get();
        if (!userDoc.exists) {
            return res.status(404).json({ error: 'User not found' });
        }

        const userData = userDoc.data();
        const totalTokensConsumed = userData.totalTokensConsumed || 0;
        const totalTokenLimit = userData.totalTokenLimit || 0;

        if (totalTokensConsumed >= totalTokenLimit) {
            return res.status(403).json({ error: 'Token limit exceeded' });
        }

        // Access Gemini API key
        const geminiApiKey = GEMINI_API_KEY.value();

        // Make a POST request to Gemini API
        const geminiResponse = await axios.post(`https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro-latest:generateContent?key=${geminiApiKey}`, req.body, {
            headers: {
                'Content-Type': 'application/json',
            },
        });

        // Extract the total token count from the usage metadata
        const totalTokenCount = geminiResponse.data.usageMetadata.totalTokenCount;

        // Update Firestore with the new token count
        await userRef.update({
            totalTokensConsumed: totalTokensConsumed + totalTokenCount
        });

        // Send the original response from the Gemini API
        res.json(geminiResponse.data);
    } catch (error) {
        console.error('Error in Gemini request:', error);
        res.status(500).json({ error: 'Failed to contact Gemini API' });
    }
});
