package com.robust1197.xhslogin;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {
    private static final String XHS_URL = "https://www.xiaohongshu.com/explore";
    private static final String SECRET_URL =
            "https://github.com/Robust1197/pathToFreedeom/settings/secrets/actions/new";

    private WebView webView;
    private TextView status;
    private ClipboardManager clipboard;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);

        status = new TextView(this);
        status.setText("请在下面正常登录小红书。登录完成后点击“同步登录态”。");
        status.setTextSize(15);
        status.setTextColor(Color.rgb(17, 24, 39));
        status.setPadding(dp(14), dp(12), dp(14), dp(12));
        root.addView(status, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
        ));

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(8), 0, dp(8), dp(8));

        Button reload = new Button(this);
        reload.setText("刷新");
        reload.setOnClickListener(v -> webView.reload());
        bar.addView(reload, new LinearLayout.LayoutParams(0, dp(48), 1));

        Button sync = new Button(this);
        sync.setText("同步登录态");
        sync.setOnClickListener(v -> syncCookieToGitHub());
        LinearLayout.LayoutParams syncLp = new LinearLayout.LayoutParams(0, dp(48), 2);
        syncLp.setMarginStart(dp(8));
        bar.addView(sync, syncLp);

        Button clear = new Button(this);
        clear.setText("清除剪贴板");
        clear.setOnClickListener(v -> clearClipboard());
        LinearLayout.LayoutParams clearLp = new LinearLayout.LayoutParams(0, dp(48), 1);
        clearLp.setMarginStart(dp(8));
        bar.addView(clear, clearLp);

        root.addView(bar);

        webView = new WebView(this);
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setLoadsImagesAutomatically(true);
        s.setSupportZoom(true);
        s.setBuiltInZoomControls(true);
        s.setDisplayZoomControls(false);

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(webView, true);

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView view, String url) {
                CookieManager.getInstance().flush();
                updateStatus();
            }
        });
        webView.setWebChromeClient(new WebChromeClient());

        root.addView(webView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1
        ));

        setContentView(root);
        webView.loadUrl(XHS_URL);
    }

    private void updateStatus() {
        String cookie = CookieManager.getInstance().getCookie("https://www.xiaohongshu.com");
        if (hasSession(cookie)) {
            status.setText("已检测到小红书登录态。点击“同步登录态”即可更新 GitHub。");
            status.setTextColor(Color.rgb(4, 120, 87));
        } else {
            status.setText("尚未检测到有效登录态。请继续在下方完成扫码 / 短信 / 安全验证。");
            status.setTextColor(Color.rgb(154, 52, 18));
        }
    }

    private boolean hasSession(String cookie) {
        if (cookie == null || cookie.isEmpty()) return false;
        return cookie.contains("web_session=")
                || cookie.contains("a1=")
                || cookie.contains("webId=");
    }

    private void syncCookieToGitHub() {
        CookieManager.getInstance().flush();
        String cookie = CookieManager.getInstance().getCookie("https://www.xiaohongshu.com");
        if (!hasSession(cookie)) {
            Toast.makeText(this, "还没有检测到有效登录态，请先完成小红书登录。", Toast.LENGTH_LONG).show();
            updateStatus();
            return;
        }

        clipboard.setPrimaryClip(ClipData.newPlainText("XHS_COOKIE", cookie));
        status.setText(
                "登录态已经复制。GitHub 打开后：\n" +
                "1. Name 填 XHS_COOKIE\n" +
                "2. Secret 粘贴剪贴板内容\n" +
                "3. 点 Add secret\n" +
                "完成后回到这里点“清除剪贴板”。"
        );
        status.setTextColor(Color.rgb(29, 78, 216));

        Toast.makeText(
                this,
                "已复制登录态。GitHub Secret 名称填 XHS_COOKIE。",
                Toast.LENGTH_LONG
        ).show();

        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(SECRET_URL)));
        } catch (Exception e) {
            Toast.makeText(this, "无法打开 GitHub，请手动打开仓库 Secrets 页面。", Toast.LENGTH_LONG).show();
        }
    }

    private void clearClipboard() {
        clipboard.setPrimaryClip(ClipData.newPlainText("", ""));
        Toast.makeText(this, "剪贴板已清除。", Toast.LENGTH_SHORT).show();
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
