import argparse, json, numpy as np
import matplotlib.pyplot as plt

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--out', dest='outdir', required=True)
    args = ap.parse_args()

    with open(args.inp, 'r') as f:
        data = json.load(f)

    ulps = np.array(data.get('ulp_values', [0]))
    if ulps.size == 0:
        print("No ULP data found")
        return

    # Histogram of ULP
    plt.figure()
    plt.hist(ulps, bins=100)
    plt.title("ULP Error Histogram")
    plt.xlabel("ULP")
    plt.ylabel("Count")
    plt.savefig(f"{args.outdir}/ulp_hist.png", bbox_inches='tight')
    plt.close()

    # CDF
    sorted_ulps = np.sort(ulps)
    cdf = np.arange(1, len(sorted_ulps)+1) / len(sorted_ulps)
    plt.figure()
    plt.plot(sorted_ulps, cdf)
    plt.title("ULP Error CDF")
    plt.xlabel("ULP")
    plt.ylabel("CDF")
    plt.savefig(f"{args.outdir}/ulp_cdf.png", bbox_inches='tight')
    plt.close()

if __name__ == "__main__":
    main()
