# Neuro-AI Cognitive Assessment App

Flutter front-end for the Cognitive Assessment System (EEG + Audio + Behavioral).

## Cognitive scoring overview

- **Behavioral score (B)**  
  - Derived from the game-based tasks (memory, attention, language).  
  - Uses **accuracy** (correct trials / total trials) and **average reaction time** to produce a behavioral performance score normalised to \([0, 100]\).

- **EEG score (E)**  
  - EEG features (band power, entropy, HRV, etc.) are extracted from the uploaded EEG file.  
  - A trained EEG model outputs a **mental effort value** in \([0, 1]\) and a **load level** (Low / Medium / High).  
  - The EEG score is computed as **E = effort × 100**, so \(E \in [0, 100]\).

- **Audio score (A)**  
  - Speech samples from the audio task are analysed for fluency.  
  - The audio model returns a **fluency score** between 0 and 100 and a label (Low / Medium / High).  
  - This fluency score is used directly as the audio score **A**.

- **Hybrid cognitive score (C)**  
  - The final cognitive score combines all three components:  
    \[
    C = 0.5 \times B + 0.3 \times E + 0.2 \times A
    \]
  - \(C \in [0, 100]\) and is displayed on the **Cognitive Profile** screen alongside EEG, Audio, and Behavioral breakdowns.

The Flutter app calls the Flask backend to run these calculations and then renders the **Cognitive Profile** report (explanation, analysis breakdown, EEG/Audio cards, and behavioral summary).
