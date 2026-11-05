package com.iconformatter.pack;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.EditText;
import android.widget.GridView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Icon pack browser: every icon of the pack with the app it belongs to
 * (label, package, and whether that app is installed on this phone).
 * Data comes from assets/mapping.json written by Icon Formatter.
 */
public class MainActivity extends Activity {

    static final class Item {
        String label, pkg, drawable;
        int res;
        boolean installed;
    }

    private final List<Item> all = new ArrayList<>();
    private final List<Item> shown = new ArrayList<>();
    private BaseAdapter adapter;

    private int dp(float v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        load();

        int accent;
        try {
            accent = Color.parseColor(getString(R.string.accent));
        } catch (Exception e) {
            accent = 0xFFBA4CD4;
        }
        // packs built on the phone share one base APK: name and accent come from assets/pack.json
        String packTitle = getString(R.string.app_name);
        try (InputStream in = getAssets().open("pack.json")) {
            JSONObject meta = new JSONObject(readAll(in));
            if (meta.has("accent")) accent = Color.parseColor(meta.getString("accent"));
            if (meta.has("name")) packTitle = meta.getString("name");
        } catch (Exception ignored) {
            // Windows build: values are compiled into the resources
        }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        // dark background with a soft accent glow, like Icon Formatter's backdrop
        GradientDrawable rootBg = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{(accent & 0x00FFFFFF) | 0x33000000, 0xFF0E0E0F, 0xFF0E0E0F});
        root.setBackground(rootBg);
        root.setPadding(dp(16), dp(28), dp(16), 0);
        // edge-to-edge (enforced on Android 15+): keep content below the status bar
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            @SuppressWarnings("deprecation") int top = insets.getSystemWindowInsetTop();
            @SuppressWarnings("deprecation") int bottom = insets.getSystemWindowInsetBottom();
            v.setPadding(dp(16), top + dp(12), dp(16), bottom);
            return insets;
        });

        // header: accent tile + name, as in Icon Formatter's title bar
        LinearLayout head = new LinearLayout(this);
        head.setGravity(Gravity.CENTER_VERTICAL);
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.mipmap.ic_launcher);
        head.addView(logo, new LinearLayout.LayoutParams(dp(30), dp(30)));
        TextView title = new TextView(this);
        title.setText(packTitle);
        title.setTextColor(0xFFE9E7E2);
        title.setTextSize(22);
        title.setPadding(dp(10), 0, 0, 0);
        title.setTypeface(android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL));
        head.addView(title);
        root.addView(head);

        int installed = 0;
        for (Item i : all) if (i.installed) installed++;
        TextView sub = new TextView(this);
        sub.setText(String.format(Locale.ITALY, "%d icone · %d app installate su questo telefono", all.size(), installed));
        sub.setTextColor(0xFF9E9B94);
        sub.setTextSize(13);
        sub.setPadding(0, dp(4), 0, dp(10));
        root.addView(sub);

        EditText search = new EditText(this);
        search.setHint("Cerca per nome o package");
        search.setHintTextColor(0xFF6E6C67);
        search.setTextColor(0xFFE9E7E2);
        search.setSingleLine(true);
        GradientDrawable sbg = new GradientDrawable();
        sbg.setColor(0x66232226);
        sbg.setCornerRadius(dp(24));
        sbg.setStroke(dp(1), (accent & 0x00FFFFFF) | 0x55000000);
        search.setBackground(sbg);
        search.setPadding(dp(14), dp(10), dp(14), dp(10));
        root.addView(search);

        GridView grid = new GridView(this);
        grid.setNumColumns(GridView.AUTO_FIT);
        grid.setColumnWidth(dp(96));
        grid.setVerticalSpacing(dp(10));
        grid.setHorizontalSpacing(dp(8));
        grid.setStretchMode(GridView.STRETCH_COLUMN_WIDTH);
        grid.setPadding(0, dp(12), 0, dp(24));
        grid.setClipToPadding(false);
        final int fAccent = accent;
        adapter = new BaseAdapter() {
            @Override public int getCount() { return shown.size(); }
            @Override public Object getItem(int p) { return shown.get(p); }
            @Override public long getItemId(int p) { return p; }

            @Override
            public View getView(int p, View convert, ViewGroup parent) {
                Item it = shown.get(p);
                LinearLayout cell = new LinearLayout(MainActivity.this);
                cell.setOrientation(LinearLayout.VERTICAL);
                cell.setGravity(Gravity.CENTER_HORIZONTAL);
                cell.setPadding(dp(4), dp(8), dp(4), dp(8));
                GradientDrawable bg = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{0x40FFFFFF & 0x22FFFFFF | 0x1A000000, 0x14FFFFFF});
                bg.setCornerRadius(dp(20));
                bg.setStroke(dp(1), 0x26FFFFFF);
                cell.setBackground(bg);
                ImageView iv = new ImageView(MainActivity.this);
                if (it.res != 0) iv.setImageResource(it.res);
                cell.addView(iv, new LinearLayout.LayoutParams(dp(56), dp(56)));
                TextView label = new TextView(MainActivity.this);
                label.setText(it.label);
                label.setTextColor(0xFFE9E7E2);
                label.setTextSize(12);
                label.setMaxLines(2);
                label.setGravity(Gravity.CENTER);
                label.setPadding(0, dp(6), 0, 0);
                cell.addView(label);
                TextView pkg = new TextView(MainActivity.this);
                pkg.setText(it.pkg.isEmpty() ? "—" : it.pkg);
                pkg.setTextColor(it.installed ? fAccent : 0xFF6E6C67);
                pkg.setTextSize(9);
                pkg.setSingleLine(true);
                pkg.setGravity(Gravity.CENTER);
                cell.addView(pkg);
                return cell;
            }
        };
        grid.setAdapter(adapter);
        root.addView(grid, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int a, int b, int c) {}
            @Override public void onTextChanged(CharSequence s, int a, int b, int c) {}
            @Override public void afterTextChanged(Editable s) { filter(s.toString()); }
        });
        filter("");
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        setContentView(root);
    }

    private void filter(String q) {
        String f = q.trim().toLowerCase(Locale.ROOT);
        shown.clear();
        for (Item i : all) {
            if (f.isEmpty() || i.label.toLowerCase(Locale.ROOT).contains(f) || i.pkg.toLowerCase(Locale.ROOT).contains(f)) shown.add(i);
        }
        if (adapter != null) adapter.notifyDataSetChanged();
    }

    private static String readAll(InputStream in) throws java.io.IOException {
        ByteArrayOutputStream bo = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
        return bo.toString("UTF-8");
    }

    private void load() {
        try (InputStream in = getAssets().open("mapping.json")) {
            JSONArray arr = new JSONArray(readAll(in));
            PackageManager pm = getPackageManager();
            for (int k = 0; k < arr.length(); k++) {
                JSONObject o = arr.getJSONObject(k);
                Item it = new Item();
                it.label = o.optString("label");
                it.pkg = o.optString("package");
                it.drawable = o.optString("drawable");
                it.res = getResources().getIdentifier(it.drawable, "drawable", getPackageName());
                try {
                    pm.getPackageInfo(it.pkg, 0);
                    it.installed = !it.pkg.isEmpty();
                } catch (Exception e) {
                    it.installed = false;
                }
                all.add(it);
            }
        } catch (Exception ignored) {
            // empty pack
        }
    }
}
