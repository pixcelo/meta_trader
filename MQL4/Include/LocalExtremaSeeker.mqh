class LocalExtremaSeeker
{
public:
    struct Point {
        double value;
        datetime timestamp;
        bool isPeak;
    };

private:
    Point points[];
    int depth;         // 新しい高値または安値を描画するために必要な最小のバー数を指定
    double deviation;  // 新しいピークや谷を描画するための最小の価格変動
    int backstep;      // 2つの連続する頂点の間の最小のバー数

public:
    LocalExtremaSeeker(int d=7, double dev=0.0, int bs=3) {
        depth = d;
        deviation = dev;
        backstep = bs;
    }

    // Peakを見つける
    void findPeaks(double &prices[], datetime &times[]) {
        ArrayResize(points, 0);
        int lastPeakIndex = -backstep;

        for (int i = depth; i < ArraySize(prices) - depth; i++) {
            bool isPeak = true;
            for (int j = 1; j <= depth; j++) {
                if (prices[i] <= prices[i-j] || prices[i] <= prices[i+j]) {
                    isPeak = false;
                    break;
                }
            }

            bool isFarEnoughFromLastPeak = (i - lastPeakIndex) >= backstep;
            bool isInitialPointOrExceedsDeviation = ArraySize(points) == 0 || prices[i] - points[ArraySize(points)-1].value >= deviation;

            if (isPeak && isFarEnoughFromLastPeak && isInitialPointOrExceedsDeviation) {
                Point pt;
                pt.value = prices[i];
                pt.timestamp = times[i];
                pt.isPeak = true;
                
                int newSize = ArraySize(points) + 1;
                ArrayResize(points, newSize);
                points[newSize - 1] = pt;

                lastPeakIndex = i;
            }
        }
    }

    // Valleyを見つける
    void findValleys(double &prices[], datetime &times[]) {
        ArrayResize(points, 0);
        int lastValleyIndex = -backstep;

        for (int i = depth; i < ArraySize(prices) - depth; i++) {
            bool isValley = true;
            for (int j = 1; j <= depth; j++) {
                if (prices[i] >= prices[i-j] || prices[i] >= prices[i+j]) {
                    isValley = false;
                    break;
                }
            }

            bool isFarEnoughFromLastValley = (i - lastValleyIndex) >= backstep;
            bool isInitialPointOrExceedsDeviation = ArraySize(points) == 0 || points[ArraySize(points)-1].value - prices[i] >= deviation;

            if (isValley && isFarEnoughFromLastValley && isInitialPointOrExceedsDeviation) {
                Point pt;
                pt.value = prices[i];
                pt.timestamp = times[i];
                pt.isPeak = false;
                
                int newSize = ArraySize(points) + 1;
                ArrayResize(points, newSize);
                points[newSize - 1] = pt;

                lastValleyIndex = i;
            }
        }
    }

    // ピークと谷の配列を取得する
    void getExtremaPoints(Point &outputPoints[]) {
        ArrayResize(outputPoints, ArraySize(points));
        for(int i = 0; i < ArraySize(points); i++) {
            outputPoints[i] = points[i];
        }
    }
};
