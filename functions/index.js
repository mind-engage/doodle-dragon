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
  // Set up the new user data, including default limits for text and image tokens
  const newUser = {
    uid: user.uid,
    totalTokensConsumed: 0,
    totalTokenLimit: 1000000,  // Default limit for text tokens
    imageTokensConsumed: 0,
    imageTotalTokenLimit: 4  // Default limit for image tokens
  };

  // Add the new user to Firestore with the default settings
  return admin.firestore().collection('users').doc(user.uid).set(newUser)
    .then(() => {
      console.log('User initialized successfully:', user.uid);
    })
    .catch(error => {
      console.error('Error initializing user:', error);
    });
});


// Proxy request to OpenAI API with token usage management
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

         const { model = "dall-e-2", prompt, n = 1, size = '1024x1024', responseFormat = 'b64_json' } = req.body;

        // Calculate token cost based on model and size
        let tokenCost;
        switch (model) {
            case 'dall-e-3':
                switch (size) {
                    case '1024x1024':
                        tokenCost = 0.040 * n;
                        break;
                    case '1024x1792':
                        tokenCost = 0.080 * n;
                        break;
                }
                break;
            case 'dall-e-2':
                switch (size) {
                    case '1024x1024':
                        tokenCost = 0.020 * n;
                        break;
                    case '512x512':
                        tokenCost = 0.018 * n;
                        break;
                    case '256x256':
                        tokenCost = 0.016 * n;
                        break;
                }
                break;
        }

        // Retrieve user's token usage and limit from Firestore
        const db = getFirestore();
        const userRef = db.collection('users').doc(req.user.uid);
        const userDoc = await userRef.get();
        if (!userDoc.exists) {
            return res.status(404).json({ error: 'User not found' });
        }

        const userData = userDoc.data();
        const imageTokensConsumed = userData.imageTokensConsumed || 0;
        const imageTotalTokenLimit = userData.imageTotalTokenLimit || 100; // Default limit

        if (imageTokensConsumed + tokenCost > imageTotalTokenLimit) {
            return res.status(403).json({ error: 'Image token limit exceeded' });
        }

        // Call OpenAI's image generation endpoint
        const response = await openai.images.generate({
            model: model,
            prompt: prompt,
            n: n,
            size: size,
            response_format: responseFormat,
        });

        // Update Firestore with the new token count
        await userRef.update({
            imageTokensConsumed: imageTokensConsumed + tokenCost
        });

        // Send the response from the OpenAI API
        res.json(response);
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
