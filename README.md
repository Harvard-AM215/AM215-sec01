# AM215 Section: From Messy Reviews to Battery Lifespans

In this section we will practice taking messy online reviews and turning them into something a statistician can actually work with. The goal is to estimate the distribution of laptop battery lifespans for two brands, Alpha and Beta.  

We will walk through a series of small scripts, each focused on a single step. By stringing them together you create a tidy dataset, fit a Gamma model brand by brand, and visualize the results.  

The point of this exercise is **not** memorizing shell flags or every line of code. The point is to get comfortable moving data step by step, reading scripts, and seeing how the parts line up into a pipeline.  

---

## Quick Pipeline Overview

Think of this as our assembly line:

0. `00_setup.sh` -> check/install Python packages and download the dataset  
1. `10_clean.sh` -> clean up raw reviews and extract relevant columns  
2. `20_make_ownership_lengths.sh` -> compute length of ownership between purchase and post dates  
3. `30_hf_batch.sh` -> send review text to a Hugging Face classifier for failure probabilities  
4. `40_build_lifespans.sh` -> keep only likely failures, call them lifespans  
5. `50_gamma_mle.py` -> fit Gamma parameters (MLE) for one brand’s lifespans  
6. `60_plot_gamma.py` -> plot histogram+fit and log-likelihood contour  
7. `99_run_pipeline.sh` -> run the whole thing and write reports + plots  

Each script also has a `--help` option and plenty of comments inside.

---

## Before You Begin

Several steps rely on Hugging Face, which provides access to transformer models.  
**STUDENT TODO:** Make a free account at https://huggingface.co before starting this section.  

(We will deal with generating and using a token later; for now, all you need is the account itself so you will not be delayed later.)

---

## Step by Step Walkthrough

### 0) `00_setup.sh`

This script checks for Python packages we will need at the end (`numpy, scipy, matplotlib, pandas`). If they are missing, it creates a virtual environment (`am215-venv`) and installs them.  

**STUDENT TODO:** if you see that it created a virtual environment, you need to activate it in your current shell:  
```bash
source am215-venv/bin/activate
```

It will also download the full dataset to `raw/reviews_big.tsv`.  

**STUDENT TODO:** For speed while learning, make a smaller file containing only the first 50 reviews:  
```bash
head -n 51 raw/reviews_big.tsv > raw/reviews.tsv
```

All later scripts will look for `raw/reviews.tsv` by default.

---

### 1) `10_clean.sh`

The raw file has some quirks (Windows carriage returns, too many columns). This script cleans it up and leaves you with three neat TSV files in `data/`:  
- `reviews_ascii.tsv`  
- `local_dates.tsv`  
- `body_for_llm.tsv`

Try running:  
```bash
./10_clean.sh
head data/reviews_ascii.tsv
```

---

### 2) `20_make_ownership_lengths.sh`

Now we compute how long each customer owned the battery before they wrote the review. It uses purchase and post dates, measures the gap in months, and writes the result into `data/ownership_lengths.tsv`.  

```bash
./20_make_ownership_lengths.sh
```

---

### 3) `30_hf_batch.sh`

Not every review talks about a failure. This script asks a Hugging Face classifier to decide, for each review, the probability that it really describes a battery failure. The output is `data/failure_probs.tsv`.  

Before you can run it, you need an API token. You already created a free account earlier — now it is time to generate a token and load it into your shell.  

**STUDENT TODO:**  
1. In your Hugging Face profile, go to **Settings -> Access Tokens**.  
2. Create a new token of type **Read**. Give it a name like *am215-demo*.  
3. In your terminal, create a safe directory and file:  
   ```bash
   mkdir -p ~/.secrets
   nano ~/.secrets/hf_token
   ```  
   Paste your token into that file, save, and quit the editor.  
4. Back in your shell, load it into the environment:  
   ```bash
   export HF_API_TOKEN=$(cat ~/.secrets/hf_token)
   ```  
   This will last for your current shell session only. If you close the terminal, export it again next time.  
5. If you want it to be permanent, add the same export line to your `~/.bashrc` or `~/.bash_profile` using the absolute path to the file.  

Now you are ready to classify reviews:  

```bash
./30_hf_batch.sh
```

If the API is slow or returns errors, you can use the committed cached results instead:  

```bash
./30_hf_batch.sh --use-cached
```

You can also try different models:  
- `--model 1` -> facebook/bart-large-mnli (default, reliable)  
- `--model 2` -> typeform/distilbert-base-uncased-mnli  
- `--model 3` -> MoritzLaurer/mDeBERTa-v3-base-mnli-xnli  

Or specify a Hugging Face model name directly.

---

### 4) `40_build_lifespans.sh`

This combines ownership lengths with review probabilities. Reviews above a chosen threshold are kept as lifespans, others are discarded.  

```bash
./40_build_lifespans.sh --thr 0.9
```

The result is `data/lifespans.tsv`.

---

### 5) `50_gamma_mle.py`

Now we fit a Gamma distribution (k = shape, theta = scale). The script estimates these parameters by maximum likelihood, fixes location at 0, and writes a text report with the results.  

```bash
python3 50_gamma_mle.py --tsv data/lifespans.tsv --out out/gamma.txt
```

---

### 6) `60_plot_gamma.py`

There is no substitute for looking at the results. This script produces both a histogram of the data with the fitted Gamma overlay, and a contour plot of the log likelihood in (k, theta).  

```bash
python3 60_plot_gamma.py \
  --tsv data/lifespans_Alpha.tsv \
  --k 2.0 --theta 4.0 \
  --title "Alpha lifespans - Gamma fit" \
  --outprefix out/alpha
```

Check the .png files in `out/`.

---

### 7) `99_run_pipeline.sh`

Finally, you can run the entire pipeline in one go. By default it will clean, calculate ownership, classify failures, build lifespans, fit Gamma distributions, and produce plots for both brands.  

```bash
./99_run_pipeline.sh
```

If the Hugging Face endpoint is failing, add `--use-cached`:  

```bash
./99_run_pipeline.sh --use-cached
```

---

## Wrap Up

When the pipeline finishes, look in the `out/` directory. You should see:  
- Reports: `gamma_Alpha.txt`, `gamma_Beta.txt`  
- Plots: `alpha_hist.png`, `alpha_llcontour.png`, and equivalents for Beta  

Think about whether the parameters your Gamma fits recovered resemble the true generating process. How sensitive were results to your choice of classification threshold?  

When you want coding details, look inside the scripts; their headers and comments explain the mechanics (awk, jq, curl, numpy, etc). The README is here only to give you the map of the journey.
