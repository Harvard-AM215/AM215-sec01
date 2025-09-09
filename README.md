# AM215 Section: From Messy Reviews to Battery Lifespans

In these example we'll be modeling the lifespans of laptop batteries
from two different brands, Alpha and Beta, using text review data. The
underlying model assumes a Gamma distribution which has a location and
a parameter. We'll use `scipy.optimize.minimize` to find the MLE and
generate some visualizations, but the data messy and not simply
a collection of lifespan values.

Think of this as a little data assembly line. We start with raw text
reviews data, clean just what we need, ask a model which reviews
probably describe a failure, turn "time owned" into "lifespan" for
those, and then fit a simple Gamma model brand-by-brand.

The point of this example is **not** to memorize every command, flag,
or quirk of syntax. It’s to get comfortable interacting with the
terminal, reading scripts, and seeing how different components can be
strung together into a pipeline.

You should be glancing through each script, but don't get hung up on
the details. It's more important to know what the purpose of the
script is.

## Before you start

Make sure you've created an account Hugging Face account on huggingface.co

If you’re logged into the Harvard server, request a compute node:
`srun -p general --pty bash` 

You'll need a Hugging Face API token to query the classifier
model. So create an account on huggingface.co

View this README.md with `less` (`q` to quit) or `vim` (`esc` then `:q!` to quit!)
    - scroll up/down with `j`/`k`
    - search with `/`

**Pro tip:** You can put a program in the background with `ctrl+Z` and then
foreground it with `fg`. This is nice because you won't lose your place in the
document when you go back and forth between reading and working in the command line. We'll
look at a more powerful solution (multiplexers like `screen` and `tmux`) another
time.


## Gamma Model of Battery Lifespans from Written Reviews

0. `00_setup.sh`

This first script makes sure we have the Python packages we'll need at
the end. If any of the dependencies are missing it will create
a virtual environment and install them there. If it does, be
sure to run the command you're shown to activate the environment. 

Then it pulls data from the web with `wget` and write it to `./raw/reviews.tsv`.

You can inspect the data with the `head` command.
`head -n 1` will just show the first line (the column headers).
You can use `wc -l` to count the rows in the file (e.g., n reviews + 1) 

**TODO**
To speed things up for now, make a subset of the data by redirecting the
ouput of `head` to a new file:
`head -n 51 > ./raw/reviews.tsv`
This file has the first 50 reviews and this path is what the other
scripts will use as their default data input unless you give them a
different argument.

Let's proceed!

## 1) `10_clean.sh`

The data set has some Windows carriage return characters. This script filters
theme out with `sed`.
It then extracts only the columns we care about with `cut`.
Finally, it writes three new data files. You should inspect them with head.

**The next scripts become more complex!** But part of that complexity the
implementation of a `--help` flag you can you when calling them to see how they
are used and/or what arguments and flags they take.

## 2) `20_make_ownership_lengths.sh`

We have the purchase dates and review dates in the new `./data/local_dates.tsv`,
so with this script we calculate how many months the reviewer has owned the battery before
they made their post.

## 3) `30_hf_batch.sh`

We have ownership lengths and review texts. But not all reviews are about
battery failures or anything negative at all.
We can use a transformer classifier to give us the probability of a review being
about a battery failure. Hugging Face allows us to sent queries to various
transformers through their API, but we need an API key. This script expects that
token to be in an environment variable called "HF_API_TOKEN".

---

**TODO**
- Create an account on huggingface.co
- Go to huggingface.co/settings/tokens and "Create a Token"
- Select "Read" for token type and call it something like "AM215-sec01" 
- With `nano` or `vim` edit a new file `hf_token` and paste in your token
**Tip**: You can paste into the Harvard terminal in your browser by right-clicking (or
two-finger tap) 

Now run:
`export HF_API_TOKEN="$(cat hf_token)"`

**Tip:** If you want to use this token in the future, you could add a line like
this to `~/.bashrc`, but use an absolute path to the token. You might also want
to `mv` the file to a new directory you create for tokens (e.g., `mkdir ~/.secrets`).
We'll talk more about how best to handle 'secrets' in the future. 

---

You can test it by playing with `hf_example.sh`. Give it a string as an argument and it will
ask the classifier what it thinks the probability of this being a about product failure.

The main programs used in the script ar `jq` for JSON parsing and `curl` for
sending our query to the endpoint.

The main batch script sends many reviews at once to the classifier and writes
what is returned in a new data file.

## 4) `40_build_lifespans.sh` 

With the probabilities of a review being about a failure, we can choose a
threshold and consider every review with a predicted probability above it to have
been a failure. These reviews' 'ownership length' will now be interpreted as a
lifespan (we assume the reviewer posted not long after the failure). All other
reviews below the probability are discarded. We now have a dataset of lifespans!

Try the `--help` flag to see how you might adjust the threshold.

## 5) `50_gamma_mle.py`

Now we use some Python code to:
- Find the the MLE under a Gamma model for a provided dataset using `scipy.optimize.minimize`
- Writes a report to disk

The script has sensible defaults for input (`data/lifespans.tsv`) and output (`out/gamma_fit.txt`) paths, but you can override them with `--tsv` and `--out` flags if needed.

## 6) `60_plot_gamma.py` - sanity-check with two plots

Pictures help. We plot a data histogram + fitted PDF and a log-likelihood contour around the MLE..
This script saves plots of:
- Gamma model's distribution compared to the data distribution
- MLE and contour plot of log-likelihood as a function of the parameter values

**Tip:**  This script takes many arguments, so make use of `--help` if you want to try
calling it on its own, or we can use the pipeline which is next (and last)!

## `99_pipeline.sh` - One-button pipeline (small, then big)

This pipeline chains together everything we've done so far and also separates
the data for the two Brands so we have the results of our MLE Gamma model for
each.

It cleans, computes ownership length, classifies reviews, builds lifespans, splits by brand, fits Gamma, and makes the two plots per brand.

Use its `--help` to see what arguments and flags it accepts.

Run the pipline, which again by default is using our small subset of the full
data, and inspect the output. You can try playing with the threshold as well.

Then tell the pipeline to use `./raw/reviews_big.tsv` as the input.
It can take a minute, especially with the calls to the free transformer
classifier. Now inspect your results.

## Wrap up

If you are curious, there is a file in one of the directories that demonstrates process by which the reviews were generated.
Did you recover the parameters of the true data generating process?

You should also take a look at the AM115 Colab notebook linked on Canvas.
