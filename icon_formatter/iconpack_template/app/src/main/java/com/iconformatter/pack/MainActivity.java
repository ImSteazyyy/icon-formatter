package com.iconformatter.pack;

import android.app.Activity;
import android.app.Dialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.BaseAdapter;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.GridView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
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
    // query, filter and sort state, applied by applyFilter()
    private String query = "";
    private int filterMode; // 0 all, 1 installed, 2 missing
    private boolean sortInstalled;
    private boolean styleNothing = true;
    private int styleAccent = 0xFFBA4CD4;
    private final TextView[] filterPills = new TextView[3];
    private TextView sortPill;
    // texts, overridden by pack.json meta
    private String txtCopy = "Copia package", txtOpen = "Apri app", txtCopied = "Package copiato";
    private String txtAll = "Tutte", txtInstalled = "Installate", txtMissing = "Mancanti";
    private String txtSortName = "A–Z", txtSortInstalled = "Installate prima";

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
        // style and texts of the app that made the pack (Nothing style by default)
        boolean nothing = true;
        String subFmt = "%1$d icone · %2$d app installate su questo telefono";
        String searchHint = "Cerca per nome o package";
        try (InputStream in = getAssets().open("pack.json")) {
            JSONObject meta = new JSONObject(readAll(in));
            if (meta.has("accent")) accent = Color.parseColor(meta.getString("accent"));
            if (meta.has("name")) packTitle = meta.getString("name");
            nothing = !"glass".equals(meta.optString("style", "nothing"));
            subFmt = meta.optString("sub", subFmt);
            searchHint = meta.optString("search", searchHint);
            txtCopy = meta.optString("copy", txtCopy);
            txtOpen = meta.optString("open", txtOpen);
            txtCopied = meta.optString("copied", txtCopied);
            txtAll = meta.optString("filter_all", txtAll);
            txtInstalled = meta.optString("filter_installed", txtInstalled);
            txtMissing = meta.optString("filter_missing", txtMissing);
            txtSortName = meta.optString("sort_name", txtSortName);
            txtSortInstalled = meta.optString("sort_installed", txtSortInstalled);
        } catch (Exception ignored) {
            // Windows build: values are compiled into the resources
        }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        // dark background with a soft accent glow, like Icon Formatter's backdrop
        if (nothing) {
            root.setBackgroundColor(0xFF000000);
        } else {
            GradientDrawable rootBg = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{(accent & 0x00FFFFFF) | 0x33000000, 0xFF0E0E0F, 0xFF0E0E0F});
            root.setBackground(rootBg);
        }
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
        head.setGravity(Gravity.CENTER);
        TextView title = new TextView(this);
        title.setText(packTitle);
        title.setTextColor(0xFFE9E7E2);
        title.setTextSize(nothing ? 42 : 30);
        title.setGravity(Gravity.CENTER);
        title.setLetterSpacing(nothing ? -0.01f : -0.03f);
        android.graphics.Typeface serif = null;
        if (nothing) {
            try {
                serif = android.graphics.Typeface.createFromAsset(getAssets(), "fonts/InstrumentSerif-Regular.ttf");
            } catch (Exception ignored) {
            }
        }
        title.setTypeface(serif != null ? serif : android.graphics.Typeface.create("sans-serif-black", android.graphics.Typeface.NORMAL));
        head.addView(title);
        root.addView(head);

        int installed = 0;
        for (Item i : all) if (i.installed) installed++;
        root.addView(new View(this), new LinearLayout.LayoutParams(1, dp(14)));

        EditText search = new EditText(this);
        search.setHint(searchHint);
        search.setHintTextColor(0xFF6E6C67);
        search.setTextColor(0xFFE9E7E2);
        search.setSingleLine(true);
        GradientDrawable sbg = new GradientDrawable();
        sbg.setColor(nothing ? 0x0DFFFFFF : 0x66232226);
        sbg.setCornerRadius(dp(24));
        sbg.setStroke(dp(1), nothing ? 0x24FFFFFF : ((accent & 0x00FFFFFF) | 0x55000000));
        search.setBackground(sbg);
        search.setPadding(dp(16), 0, dp(16), 0);
        search.setMinHeight(dp(48));
        search.setHeight(dp(48));
        search.setCompoundDrawablePadding(dp(12));
        search.setCompoundDrawablesRelativeWithIntrinsicBounds(new SearchIcon(dp(22)), null, null, null);
        root.addView(search);
        // filter pills and sort toggle under the search field
        styleNothing = nothing;
        styleAccent = accent;
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        filterPills[0] = pill(txtAll);
        filterPills[1] = pill(txtInstalled);
        filterPills[2] = pill(txtMissing);
        filterPills[0].setOnClickListener(v -> setFilter(0));
        filterPills[1].setOnClickListener(v -> setFilter(1));
        filterPills[2].setOnClickListener(v -> setFilter(2));
        for (TextView t : filterPills) row.addView(t, pillLp(true));
        sortPill = pill("");
        sortPill.setOnClickListener(v -> toggleSort());
        row.addView(sortPill, pillLp(false));
        refreshPills();
        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        rp.setMargins(0, dp(10), 0, dp(8));
        root.addView(row, rp);

        GridView grid = new GridView(this);
        grid.setNumColumns(3);
        grid.setVerticalSpacing(dp(10));
        grid.setHorizontalSpacing(dp(8));
        grid.setStretchMode(GridView.STRETCH_COLUMN_WIDTH);
        grid.setPadding(0, dp(14), 0, dp(24));
        grid.setClipToPadding(false);
        // rows fade out under the filters instead of being cut by a hard edge
        grid.setVerticalFadingEdgeEnabled(true);
        grid.setFadingEdgeLength(dp(28));
        grid.setOverScrollMode(View.OVER_SCROLL_NEVER);
        final int fAccent = accent;
        final boolean fNothing = nothing;
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
                cell.setPadding(dp(6), dp(6), dp(6), dp(8));
                GradientDrawable bg;
                if (fNothing) {
                    bg = new GradientDrawable();
                    bg.setColor(0xFF141414);
                } else {
                    bg = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{0x40FFFFFF & 0x22FFFFFF | 0x1A000000, 0x14FFFFFF});
                    bg.setStroke(dp(1), 0x26FFFFFF);
                }
                bg.setCornerRadius(dp(22));
                cell.setBackground(bg);
                // the icon on its own window (as in Icon Formatter's cards) with a
                // small symbol bottom right: the app is installed here or not
                FrameLayout win = new FrameLayout(MainActivity.this);
                GradientDrawable wbg = new GradientDrawable();
                wbg.setColor(fNothing ? 0xFF1C1C1C : 0x14FFFFFF);
                wbg.setCornerRadius(dp(14));
                win.setBackground(wbg);
                ImageView iv = new ImageView(MainActivity.this);
                if (it.res != 0) iv.setImageResource(it.res);
                win.addView(iv, new FrameLayout.LayoutParams(dp(52), dp(52), Gravity.CENTER));
                TextView mark = new TextView(MainActivity.this);
                mark.setText(it.installed ? "\u2713" : "\u2013");
                mark.setTextSize(12);
                mark.setTextColor(it.installed ? (fNothing ? 0xFF8FB58A : fAccent) : 0xFF5A5A5A);
                FrameLayout.LayoutParams mp = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM | Gravity.END);
                mp.setMargins(0, 0, dp(8), dp(4));
                win.addView(mark, mp);
                cell.addView(win, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(76)));
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
                pkg.setTextColor(fNothing ? (it.installed ? 0xFF929292 : 0xFF5A5A5A) : (it.installed ? fAccent : 0xFF6E6C67));
                pkg.setTextSize(9);
                pkg.setSingleLine(true);
                pkg.setGravity(Gravity.CENTER);
                cell.addView(pkg);
                return cell;
            }
        };
        grid.setAdapter(adapter);
        grid.setOnItemLongClickListener((parent, view, pos, id) -> {
            showItemDialog(shown.get(pos));
            return true;
        });
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
        query = q;
        applyFilter();
    }

    // shown = all, filtered by query and installed/missing, then sorted
    private void applyFilter() {
        String f = query.trim().toLowerCase(Locale.ROOT);
        shown.clear();
        for (Item i : all) {
            if (filterMode == 1 && !i.installed) continue;
            if (filterMode == 2 && i.installed) continue;
            if (f.isEmpty() || i.label.toLowerCase(Locale.ROOT).contains(f) || i.pkg.toLowerCase(Locale.ROOT).contains(f)) shown.add(i);
        }
        Collections.sort(shown, (a, b) -> {
            if (sortInstalled && a.installed != b.installed) return a.installed ? -1 : 1;
            return a.label.compareToIgnoreCase(b.label);
        });
        if (adapter != null) adapter.notifyDataSetChanged();
    }

    private void setFilter(int mode) {
        filterMode = mode;
        refreshPills();
        applyFilter();
    }

    private void toggleSort() {
        sortInstalled = !sortInstalled;
        refreshPills();
        applyFilter();
    }

    private void refreshPills() {
        for (int k = 0; k < 3; k++) stylePill(filterPills[k], k == filterMode);
        sortPill.setTag(sortInstalled ? txtSortInstalled : txtSortName);
        stylePill(sortPill, false);
    }

    private TextView pill(String text) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextSize(14);
        t.setSingleLine(true);
        t.setEllipsize(TextUtils.TruncateAt.END);
        t.setGravity(Gravity.CENTER);
        t.setPadding(dp(8), 0, dp(8), 0);
        t.setTag(text);
        return t;
    }

    private LinearLayout.LayoutParams pillLp(boolean weighted) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(weighted ? 0 : ViewGroup.LayoutParams.WRAP_CONTENT, dp(44), weighted ? 1f : 0f);
        lp.setMargins(dp(3), 0, dp(3), 0);
        return lp;
    }

    // same look as the app's filter pills: an outline; the selected one has a
    // soft accent fill, an accent outline and a check mark
    private void stylePill(TextView t, boolean selected) {
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(dp(22));
        Object base = t.getTag();
        String label = base instanceof String ? (String) base : t.getText().toString();
        if (selected) {
            g.setColor((styleAccent & 0x00FFFFFF) | 0x33000000);
            g.setStroke(dp(1), (styleAccent & 0x00FFFFFF) | 0xB3000000);
            t.setTextColor(0xFFFFFFFF);
            t.setText("✓ " + label);
        } else {
            g.setColor(0x00000000);
            g.setStroke(dp(1), styleNothing ? 0x24FFFFFF : ((styleAccent & 0x00FFFFFF) | 0x55000000));
            t.setTextColor(0xFFE0E0E0);
            t.setText(label);
        }
        t.setBackground(g);
    }

    private TextView action(String text, int color) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextSize(15);
        t.setTextColor(color);
        t.setPadding(0, dp(12), 0, dp(12));
        TypedValue tv = new TypedValue();
        getTheme().resolveAttribute(android.R.attr.selectableItemBackground, tv, true);
        t.setBackgroundResource(tv.resourceId);
        return t;
    }

    // long press: app name, package and the actions, in a dark card like the page
    private void showItemDialog(Item it) {
        Dialog d = new Dialog(this);
        d.requestWindowFeature(Window.FEATURE_NO_TITLE);
        d.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(20), dp(20), dp(20), dp(8));
        card.setMinimumWidth(dp(260));
        GradientDrawable cbg = new GradientDrawable();
        cbg.setColor(styleNothing ? 0xFF141414 : 0xFF1A1A1D);
        cbg.setCornerRadius(dp(22));
        cbg.setStroke(dp(1), styleNothing ? 0x14FFFFFF : 0x26FFFFFF);
        card.setBackground(cbg);
        TextView name = new TextView(this);
        name.setText(it.label);
        name.setTextColor(0xFFE9E7E2);
        name.setTextSize(18);
        card.addView(name);
        TextView pkg = new TextView(this);
        pkg.setText(it.pkg.isEmpty() ? "—" : it.pkg);
        pkg.setTextColor(0xFF929292);
        pkg.setTextSize(12);
        pkg.setPadding(0, dp(4), 0, dp(4));
        card.addView(pkg);
        TextView copy = action(txtCopy, 0xFFE9E7E2);
        copy.setOnClickListener(v -> {
            ClipboardManager cm = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            cm.setPrimaryClip(ClipData.newPlainText("package", it.pkg));
            Toast.makeText(this, txtCopied, Toast.LENGTH_SHORT).show();
            d.dismiss();
        });
        card.addView(copy);
        // shortcut: "open" only for installed apps that have a launcher entry
        Intent launch = it.installed ? getPackageManager().getLaunchIntentForPackage(it.pkg) : null;
        if (launch != null) {
            TextView open = action(txtOpen, styleAccent);
            open.setOnClickListener(v -> {
                startActivity(launch);
                d.dismiss();
            });
            card.addView(open);
        }
        d.setContentView(card);
        d.show();
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
                if (it.drawable.isEmpty() && o.has("calendar")) {
                    int day = java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_MONTH);
                    it.drawable = o.optString("calendar") + day;
                }
                it.res = getResources().getIdentifier(it.drawable, "drawable", getPackageName());
                if (it.label.isEmpty() && !it.pkg.isEmpty()) {
                    try {
                        it.label = pm.getApplicationLabel(pm.getApplicationInfo(it.pkg, 0)).toString();
                    } catch (Exception e) {
                        it.label = it.pkg;
                    }
                }
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

    /** Small magnifier, drawn so the pack needs no extra resource. */
    static final class SearchIcon extends android.graphics.drawable.Drawable {
        private final int size;
        private final android.graphics.Paint paint = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);

        SearchIcon(int size) {
            this.size = size;
            paint.setColor(0xFFA8A8A8);
            paint.setStyle(android.graphics.Paint.Style.STROKE);
            paint.setStrokeWidth(size / 11f);
            paint.setStrokeCap(android.graphics.Paint.Cap.ROUND);
        }

        @Override public void draw(android.graphics.Canvas c) {
            float r = size * 0.30f;
            float cx = size * 0.42f, cy = size * 0.42f;
            c.drawCircle(cx, cy, r, paint);
            c.drawLine(cx + r * 0.72f, cy + r * 0.72f, size * 0.84f, size * 0.84f, paint);
        }

        @Override public int getIntrinsicWidth() { return size; }
        @Override public int getIntrinsicHeight() { return size; }
        @Override public void setAlpha(int a) { paint.setAlpha(a); }
        @Override public void setColorFilter(android.graphics.ColorFilter f) { paint.setColorFilter(f); }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
    }
}
